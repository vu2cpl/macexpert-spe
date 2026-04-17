import Foundation
import ORSSerial

/// Serial connection to the SPE amplifier using ORSSerialPort.
@MainActor
final class SerialConnection: NSObject, ConnectionProvider, @unchecked Sendable {
    var isConnected: Bool { port?.isOpen ?? false }
    var onStateUpdate: ((AmplifierState) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onRCUDisplayPacket: ((Data) -> Void)?
    var onRawBytes: ((Data) -> Void)?
    /// Fires each time the RCU ticker sends a full OFF→ON cycle. Lets the
    /// view model surface a "ticks sent" counter in the debug overlay so we
    /// can see whether the ticker is even running.
    var onRCUTick: (() -> Void)?

    private var port: ORSSerialPort?
    private var portPath: String
    private var baudRate: Int
    private var pollTimer: Timer?
    private var flushTimer: Timer?
    private var rcuPollTask: Task<Void, Never>?
    private var receiveBuffer = Data()
    private var currentState = AmplifierState()
    /// When true, the periodic STATUS request is suppressed so RCU mode can
    /// stream LCD frames uninterrupted.
    private var isPollingPaused = false

    /// How often to re-issue the RCU_OFF → RCU_ON cycle during live tracking.
    /// We use the full OFF→ON cycle (not just RCU_ON) because the amp only
    /// sends a frame when its display state differs from its "last reported"
    /// marker; RCU_OFF resets that marker so the next ON always produces a
    /// fresh frame. This gives us an always-live heartbeat.
    private let rcuPollInterval: Duration = .milliseconds(400)
    /// Gap between the RCU_OFF and the following RCU_ON within one cycle.
    private let rcuOffOnGap: Duration = .milliseconds(60)

    /// After this long without any new bytes while we have an open 0x6A frame
    /// in the buffer, flush it as a complete frame. The 1.5K-FA sends one
    /// frame per LCD change and then goes silent, so we can't rely on a
    /// closing sync to delimit frames.
    private let quietFlushInterval: TimeInterval = 0.25

    // Polling intervals (seconds)
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

        serialPort.open()

        // Wait briefly for port to open
        try await Task.sleep(for: .milliseconds(200))

        guard serialPort.isOpen else {
            throw ConnectionError.failedToOpen(portPath)
        }

        onConnectionChange?(true)

        // Send initial status request
        sendCommand(.status)

        // Start both pollers: CSV @ 1Hz for detailed op-mode data, RCU @ ~2/s
        // for live LCD mirroring (cursor, sub-menu state, checkbox state).
        // The two don't interfere — the CSV parser only consumes frames with
        // CNT=0x43, and RCU frames have CNT=0x6A.
        startPolling()
        startRCUPolling()
    }

    func disconnect() {
        stopPolling()
        stopRCUPolling()
        flushTimer?.invalidate()
        flushTimer = nil
        port?.close()
        port = nil
        onConnectionChange?(false)
    }

    func sendCommand(_ command: SPECommand) {
        guard let port, port.isOpen else { return }
        let packet = SPEProtocol.buildPacket(command: command)
        port.send(packet)
    }

    /// Power on the amplifier via DTR/RTS line sequence.
    /// Sequence from OH2GEK power_spe_on.py:
    ///   DTR=1 -> DTR=0 -> RTS=1 -> wait 1s -> DTR=1 -> RTS=0
    /// Startup takes 3-4.5 seconds after this sequence.
    func powerOn() async {
        guard let port, port.isOpen else { return }
        port.dtr = true
        port.dtr = false
        port.rts = true
        try? await Task.sleep(for: .seconds(1))
        port.dtr = true
        port.rts = false
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        schedulePoll()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func schedulePoll() {
        let interval = currentState.isActive ? activePollInterval : idlePollInterval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPollingPaused {
                    self.sendCommand(.status)
                }
                self.schedulePoll()
            }
        }
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
        // Capture the intervals outside the Task so we don't have to access
        // @MainActor-isolated properties from the Task's non-main context.
        let interval = rcuPollInterval
        let gap = rcuOffOnGap
        // Mark the Task @MainActor so sendCommand calls are legal without
        // await MainActor.run hops. On macOS 14+ with SwiftUI, this is the
        // most reliable way to run a heartbeat.
        rcuPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.sendCommand(.rcuOff)
                try? await Task.sleep(for: gap)
                guard !Task.isCancelled else { return }
                self.sendCommand(.rcuOn)
                self.onRCUTick?()
            }
        }
    }

    private func stopRCUPolling() {
        rcuPollTask?.cancel()
        rcuPollTask = nil
    }

    /// Parse any pending 0x6A frame out of the buffer even without a closing
    /// sync. Called by the quiet-period flush timer.
    private func forceFlushOpenFrame() {
        // Mimic RCUDisplayPacket.find but accept end-of-buffer as the frame end.
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
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: quietFlushInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.forceFlushOpenFrame()
            }
        }
    }

    // MARK: - Data Processing

    private func processReceivedData(_ data: Data) {
        // Surface raw bytes to anyone listening (capture pipeline) BEFORE parsing,
        // so we can diagnose framing issues even when no parser matches.
        onRawBytes?(data)
        receiveBuffer.append(data)
        // Re-arm the quiet-period flush: if more bytes arrive, the timer
        // resets; if nothing comes for quietFlushInterval, we'll emit any
        // open 0x6A frame we've accumulated.
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

        // Drain any RCU 106-byte LCD display packets (CNT=0x6A) and forward
        // their data bytes to the capture pipeline. Loops because multiple
        // frames may have arrived in one chunk.
        while let frame = RCUDisplayPacket.find(in: receiveBuffer) {
            onRCUDisplayPacket?(Data(frame.dataBytes))
            receiveBuffer.removeSubrange(..<frame.range.upperBound)
        }

        // Prevent buffer from growing indefinitely
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
