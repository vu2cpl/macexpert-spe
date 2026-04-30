import Foundation
import ORSSerial

/// Serial connection to the SPE amplifier using ORSSerialPort.
///
/// Threading model:
/// * Public API (`sendCommand`, `connect`, `disconnect`, `powerOn`,
///   `enableRCU`, etc.) is callable from the main actor and returns
///   immediately. The actual port I/O is queued onto `ioQueue`.
/// * `ioQueue` is a private serial DispatchQueue; every `port.send()`,
///   `port.dtr =`, `port.rts =`, `port.open()`, `port.close()` runs
///   there. If ORSSerialPort's `send()` blocks (cable unplugged
///   mid-write, FTDI buffer full, kernel TX queue not draining), only
///   that queue blocks — never the main thread, never the UI.
/// * Timer-driven writes (CSV poll + RCU OFF/ON ticker) use
///   `DispatchSourceTimer` running on `ioQueue`, so they never bounce
///   through the main actor.
/// * UI-affecting state (`currentState`, `receiveBuffer`) and
///   callbacks (`onStateUpdate`, `onConnectionChange`,
///   `onRCUDisplayPacket`, `onRawBytes`, `onRCUTick`) are touched only
///   on the main actor via explicit `Task { @MainActor in ... }` hops
///   from the I/O queue.
@MainActor
final class SerialConnection: NSObject, ConnectionProvider, @unchecked Sendable {
    var isConnected: Bool { port?.isOpen ?? false }
    var onStateUpdate: ((AmplifierState) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onRCUDisplayPacket: ((Data) -> Void)?
    var onRawBytes: ((Data) -> Void)?
    /// Fires each time the RCU ticker sends a full OFF→ON cycle.
    var onRCUTick: (() -> Void)?

    private var port: ORSSerialPort?
    private var portPath: String
    private var baudRate: Int

    /// All blocking serial I/O happens here. Serial queue (single
    /// concurrent operation) so writes don't interleave on the wire.
    private let ioQueue = DispatchQueue(label: "MacExpert.SerialIO",
                                        qos: .userInitiated)

    /// Background timers for CSV polling and RCU heartbeat. They run
    /// on `ioQueue` so the timer firings AND the writes they trigger
    /// are off the main thread.
    private var pollTimer: DispatchSourceTimer?
    private var rcuTimer: DispatchSourceTimer?
    private var flushTimer: DispatchSourceTimer?

    private var receiveBuffer = Data()
    private var currentState = AmplifierState()
    /// When true, the periodic STATUS request is suppressed so RCU mode can
    /// stream LCD frames uninterrupted.
    private var isPollingPaused = false

    /// How often to re-issue the RCU_OFF → RCU_ON cycle during live tracking.
    /// Full OFF→ON cycle (not just RCU_ON) because the amp only sends a frame
    /// when its display state differs from its "last reported" marker;
    /// RCU_OFF resets that marker so the next ON always produces a fresh
    /// frame.
    private let rcuPollInterval: TimeInterval = 0.4
    /// Gap between the RCU_OFF and the following RCU_ON within one cycle.
    private let rcuOffOnGap: TimeInterval = 0.06

    /// After this long without any new bytes while we have an open 0x6A
    /// frame in the buffer, flush it as a complete frame. The 1.5K-FA sends
    /// one frame per LCD change and then goes silent, so we can't rely on
    /// a closing sync to delimit frames.
    private let quietFlushInterval: TimeInterval = 0.25

    // CSV polling intervals (seconds)
    private let activePollInterval: TimeInterval = 0.2
    private let idlePollInterval: TimeInterval = 1.0

    init(portPath: String, baudRate: Int = 115200) {
        self.portPath = portPath
        self.baudRate = baudRate
        super.init()
    }

    func configure(portPath: String, baudRate: Int) {
        self.portPath = portPath
        self.baudRate = baudRate
    }

    func connect() async throws {
        guard let serialPort = ORSSerialPort(path: portPath) else {
            throw ConnectionError.portNotFound(portPath)
        }

        port = serialPort
        serialPort.baudRate = NSNumber(value: baudRate)
        serialPort.numberOfStopBits = 1
        serialPort.parity = .none
        serialPort.usesRTSCTSFlowControl = false
        serialPort.usesDTRDSRFlowControl = false
        serialPort.usesDCDOutputFlowControl = false
        serialPort.delegate = self

        // open() can also block in degenerate cases — push to ioQueue.
        ioQueue.async { serialPort.open() }

        // Wait briefly for port to open.
        try await Task.sleep(for: .milliseconds(200))

        guard serialPort.isOpen else {
            throw ConnectionError.failedToOpen(portPath)
        }

        onConnectionChange?(true)

        // Send initial status request
        sendCommand(.status)

        // Start both pollers: CSV @ 1Hz for detailed op-mode data, RCU
        // @ ~2/s for live LCD mirroring (cursor, sub-menu state,
        // checkbox state). The two don't interfere — the CSV parser
        // only consumes frames with CNT=0x43, RCU frames are 0x6A.
        startPolling()
        startRCUPolling()
    }

    func disconnect() {
        stopPolling()
        stopRCUPolling()
        cancelFlushTimer()
        let portRef = port
        port = nil
        ioQueue.async { portRef?.close() }
        onConnectionChange?(false)
    }

    func sendCommand(_ command: SPECommand) {
        // Never call port.send() from the main thread — it can block in
        // the kernel for as long as the FTDI TX buffer takes to drain
        // (potentially seconds, or forever if the device hangs). Hand
        // off to ioQueue and return immediately.
        guard let portRef = port else { return }
        let packet = SPEProtocol.buildPacket(command: command)
        ioQueue.async {
            guard portRef.isOpen else { return }
            portRef.send(packet)
        }
    }

    /// Power on the amplifier via DTR/RTS line sequence.
    /// Sequence from OH2GEK power_spe_on.py:
    ///   DTR=1 -> DTR=0 -> RTS=1 -> wait 1s -> DTR=1 -> RTS=0
    /// Startup takes 3-4.5 seconds after this sequence.
    func powerOn() async {
        guard let portRef = port else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ioQueue.async {
                guard portRef.isOpen else { cont.resume(); return }
                portRef.dtr = true
                portRef.dtr = false
                portRef.rts = true
                Thread.sleep(forTimeInterval: 1.0)
                portRef.dtr = true
                portRef.rts = false
                cont.resume()
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        schedulePoll()
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// Schedule the next CSV STATUS poll. Runs on `ioQueue` so the
    /// write happens off the main thread, even when the timer fires
    /// during a heavy UI update.
    private func schedulePoll() {
        let interval = currentState.isActive ? activePollInterval : idlePollInterval
        let isPaused = isPollingPaused
        let portRef = port
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            if !isPaused, let portRef, portRef.isOpen {
                let packet = SPEProtocol.buildPacket(command: .status)
                portRef.send(packet)
            }
            // Reschedule on the main actor so we read currentState
            // (which may have changed in the meantime) consistently.
            Task { @MainActor [weak self] in
                self?.schedulePoll()
            }
        }
        timer.resume()
        pollTimer = timer
    }

    /// Pause periodic STATUS polling. Required during RCU capture: status
    /// requests would interleave with RCU traffic and confuse the parser.
    func pausePolling() { isPollingPaused = true }

    /// Resume periodic STATUS polling.
    func resumePolling() { isPollingPaused = false }

    /// Enable RCU mode and start a live-heartbeat ticker. Every tick the
    /// ticker sends an RCU_OFF → brief gap → RCU_ON cycle, which guarantees
    /// a fresh frame each interval even on static screens. Ownership is
    /// managed by the view model via enableRCU/disableRCU.
    func enableRCU() {
        sendCommand(.rcuOn)
        startRCUPolling()
    }

    /// Stop the ticker and disable RCU mode.
    func disableRCU() {
        stopRCUPolling()
        sendCommand(.rcuOff)
    }

    private func startRCUPolling() {
        stopRCUPolling()
        let interval = rcuPollInterval
        let gap = rcuOffOnGap
        let portRef = port
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let portRef, portRef.isOpen else { return }
            // OFF then small gap then ON. Both writes happen on
            // ioQueue serially so they can't be interleaved by another
            // command write. Thread.sleep is OK here — we're on a
            // background queue, the main thread is unaffected.
            let off = SPEProtocol.buildPacket(command: .rcuOff)
            let on  = SPEProtocol.buildPacket(command: .rcuOn)
            portRef.send(off)
            Thread.sleep(forTimeInterval: gap)
            portRef.send(on)
            Task { @MainActor [weak self] in
                self?.onRCUTick?()
            }
        }
        timer.resume()
        rcuTimer = timer
    }

    private func stopRCUPolling() {
        rcuTimer?.cancel()
        rcuTimer = nil
    }

    // MARK: - Quiet-period flush for unterminated 0x6A frames

    /// Parse any pending 0x6A frame out of the buffer even without a closing
    /// sync. Called by the quiet-period flush timer.
    private func forceFlushOpenFrame() {
        guard receiveBuffer.count >= 4 else { return }
        for i in 0...(receiveBuffer.count - 4) {
            if receiveBuffer[i] == 0xAA,
               receiveBuffer[i+1] == 0xAA,
               receiveBuffer[i+2] == 0xAA,
               receiveBuffer[i+3] == RCUDisplayPacket.typeMarker {
                let dataStart = i + 4
                let dataSlice = Array(receiveBuffer[dataStart..<receiveBuffer.count])
                onRCUDisplayPacket?(Data(dataSlice))
                receiveBuffer.removeAll()
                return
            }
        }
    }

    private func scheduleFlushTimer() {
        cancelFlushTimer()
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + quietFlushInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.forceFlushOpenFrame()
            }
        }
        timer.resume()
        flushTimer = timer
    }

    private func cancelFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    // MARK: - Data Processing

    private func processReceivedData(_ data: Data) {
        // Surface raw bytes to anyone listening (capture pipeline) BEFORE parsing.
        onRawBytes?(data)
        receiveBuffer.append(data)
        // Re-arm the quiet-period flush.
        scheduleFlushTimer()

        // Parse CSV status responses (CNT=0x43 = 67 bytes)
        while let range = findStatusResponse(in: receiveBuffer) {
            let responseData = receiveBuffer.subdata(in: range)
            if let csvString = SPEProtocol.extractStatusData(from: responseData) {
                if let state = SPEProtocol.parseStatus(csvString) {
                    currentState = state
                    onStateUpdate?(state)
                }
            }
            receiveBuffer.removeSubrange(..<range.upperBound)
        }

        // Drain any RCU 0x6A LCD display frames.
        while let frame = RCUDisplayPacket.find(in: receiveBuffer) {
            onRCUDisplayPacket?(Data(frame.dataBytes))
            receiveBuffer.removeSubrange(..<frame.range.upperBound)
        }

        // Prevent buffer from growing indefinitely.
        if receiveBuffer.count > 4096 {
            receiveBuffer.removeAll()
        }
    }

    private func findStatusResponse(in data: Data) -> Range<Int>? {
        guard data.count >= 6 else { return nil }
        for i in 0..<(data.count - 3) {
            if data[i] == 0xAA && data[i+1] == 0xAA && data[i+2] == 0xAA {
                // CRITICAL: only consume frames whose CNT byte is 0x43 (the
                // CSV status length). Without this guard, this parser also
                // eats proprietary 0x6A display packets in RCU mode, which
                // then never reach the RCUDisplayPacket parser.
                guard data[i+3] == SPEProtocol.statusLength else { return nil }

                let length = Int(data[i+3])
                // Total: 3 sync + 1 length + N data + 2 checksum + 2 CRLF
                let totalLength = 3 + 1 + length + 2 + 2
                let endIndex = i + totalLength

                guard endIndex <= data.count else { return nil }
                return i..<endIndex
            }
        }
        return nil
    }

    // MARK: - Port Discovery

    static var availablePorts: [ORSSerialPort] {
        ORSSerialPortManager.shared().availablePorts
    }
}

// MARK: - ORSSerialPortDelegate

extension SerialConnection: ORSSerialPortDelegate {
    nonisolated func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            onConnectionChange?(true)
        }
    }

    nonisolated func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            stopPolling()
            onConnectionChange?(false)
        }
    }

    nonisolated func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            disconnect()
        }
    }

    nonisolated func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        Task { @MainActor in
            processReceivedData(data)
        }
    }

    nonisolated func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        Task { @MainActor in
            print("Serial error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum ConnectionError: LocalizedError {
    case portNotFound(String)
    case failedToOpen(String)
    case websocketFailed(String)

    var errorDescription: String? {
        switch self {
        case .portNotFound(let path): "Serial port not found: \(path)"
        case .failedToOpen(let path): "Failed to open port: \(path)"
        case .websocketFailed(let msg): "WebSocket error: \(msg)"
        }
    }
}
