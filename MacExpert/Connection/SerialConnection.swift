import Foundation
import ORSSerial

/// Serial connection to the SPE amplifier using ORSSerialPort.
@MainActor
final class SerialConnection: NSObject, ConnectionProvider, @unchecked Sendable {
    var isConnected: Bool { port?.isOpen ?? false }
    var onStateUpdate: ((AmplifierState) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var port: ORSSerialPort?
    private var portPath: String
    private var baudRate: Int
    private var pollTimer: Timer?
    private var receiveBuffer = Data()
    private var currentState = AmplifierState()

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

        // Start polling
        startPolling()
    }

    func disconnect() {
        stopPolling()
        port?.close()
        port = nil
        onConnectionChange?(false)
    }

    func sendCommand(_ command: SPECommand) {
        guard let port, port.isOpen else { return }
        let packet = SPEProtocol.buildPacket(command: command)
        port.send(packet)
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
                self?.sendCommand(.status)
                self?.schedulePoll()
            }
        }
    }

    // MARK: - Data Processing

    private func processReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        // Look for complete status responses
        // Status response: 0xAA 0xAA 0xAA 0x43 [67 bytes] [CHK0] [CHK1] CR LF
        while let range = findStatusResponse(in: receiveBuffer) {
            let responseData = receiveBuffer.subdata(in: range)

            if let csvString = SPEProtocol.extractStatusData(from: responseData) {
                if let state = SPEProtocol.parseStatus(csvString) {
                    currentState = state
                    onStateUpdate?(state)
                }
            }

            // Remove processed data
            receiveBuffer.removeSubrange(..<range.upperBound)
        }

        // Prevent buffer from growing indefinitely
        if receiveBuffer.count > 4096 {
            receiveBuffer.removeAll()
        }
    }

    private func findStatusResponse(in data: Data) -> Range<Int>? {
        guard data.count >= 6 else { return nil }

        for i in 0..<(data.count - 2) {
            if data[i] == 0xAA && data[i+1] == 0xAA && data[i+2] == 0xAA {
                let lengthIndex = i + 3
                guard lengthIndex < data.count else { return nil }

                let length = Int(data[lengthIndex])
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
