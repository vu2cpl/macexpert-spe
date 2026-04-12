import SwiftUI
import ORSSerial

@Observable
@MainActor
final class AmplifierViewModel {
    // MARK: - Published State
    var state = AmplifierState()
    var isConnected = false
    var connectionMode: ConnectionMode = .serial
    var detectedModel: AmplifierModel = .unknown
    var statusMessage: String = ""
    var errorMessage: String = ""

    // Serial settings
    var selectedPortPath: String = "" {
        didSet { UserDefaults.standard.set(selectedPortPath, forKey: "serialPortPath") }
    }
    var baudRate: Int = 115200 {
        didSet { UserDefaults.standard.set(baudRate, forKey: "baudRate") }
    }
    var availablePorts: [ORSSerialPort] = []

    // WebSocket settings
    var wsHost: String = "192.168.1.100" {
        didSet { UserDefaults.standard.set(wsHost, forKey: "wsHost") }
    }
    var wsPort: Int = 8888 {
        didSet { UserDefaults.standard.set(wsPort, forKey: "wsPort") }
    }

    // MARK: - Private
    private var connection: ConnectionProvider?
    private var portObserver: NSObjectProtocol?

    init() {
        loadSettings()
        refreshPorts()
        observePortChanges()
    }

    // MARK: - Connection

    func connect() {
        Task {
            do {
                disconnect()

                switch connectionMode {
                case .serial:
                    let serial = SerialConnection(portPath: selectedPortPath, baudRate: baudRate)
                    serial.onStateUpdate = { [weak self] state in
                        self?.handleStateUpdate(state)
                    }
                    serial.onConnectionChange = { [weak self] connected in
                        self?.isConnected = connected
                        self?.statusMessage = connected ? "Connected (Serial)" : "Disconnected"
                    }
                    connection = serial
                    try await serial.connect()

                case .websocket:
                    guard let url = URL(string: "ws://\(wsHost):\(wsPort)/ws") else {
                        errorMessage = "Invalid WebSocket URL"
                        return
                    }
                    let ws = WebSocketConnection(url: url)
                    ws.onStateUpdate = { [weak self] state in
                        self?.handleStateUpdate(state)
                    }
                    ws.onConnectionChange = { [weak self] connected in
                        self?.isConnected = connected
                        self?.statusMessage = connected ? "Connected (WebSocket)" : "Disconnected"
                    }
                    connection = ws
                    try await ws.connect()
                }

                errorMessage = ""
            } catch {
                errorMessage = error.localizedDescription
                isConnected = false
            }
        }
    }

    func disconnect() {
        connection?.disconnect()
        connection = nil
        isConnected = false
        statusMessage = "Disconnected"
    }

    func sendCommand(_ command: SPECommand) {
        connection?.sendCommand(command)
    }

    /// Power on via WebSocket (DTR toggle, only available in WS mode via spe-remote)
    func powerOn() {
        guard connectionMode == .websocket, let ws = connection as? WebSocketConnection else {
            errorMessage = "Power On only available via WebSocket"
            return
        }
        ws.sendRawCommand("power_on")
    }

    func powerOff() {
        if connectionMode == .websocket, let ws = connection as? WebSocketConnection {
            ws.sendRawCommand("power_off")
        } else {
            sendCommand(.switchOff)
        }
    }

    // MARK: - Port Management

    func refreshPorts() {
        availablePorts = SerialConnection.availablePorts
        if selectedPortPath.isEmpty, let first = availablePorts.first {
            selectedPortPath = first.path
        }
    }

    // MARK: - Private

    private func handleStateUpdate(_ newState: AmplifierState) {
        state = newState

        // Auto-detect model from ID field (serial mode)
        if !newState.modelId.isEmpty {
            let model = AmplifierModel.detect(from: newState.modelId)
            if model != .unknown {
                detectedModel = model
            }
        }
    }

    private func loadSettings() {
        if let path = UserDefaults.standard.string(forKey: "serialPortPath") {
            selectedPortPath = path
        }
        let savedBaud = UserDefaults.standard.integer(forKey: "baudRate")
        if savedBaud > 0 { baudRate = savedBaud }

        if let host = UserDefaults.standard.string(forKey: "wsHost"), !host.isEmpty {
            wsHost = host
        }
        let savedWSPort = UserDefaults.standard.integer(forKey: "wsPort")
        if savedWSPort > 0 { wsPort = savedWSPort }
    }

    private func observePortChanges() {
        portObserver = NotificationCenter.default.addObserver(
            forName: .ORSSerialPortsWereConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPorts()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .ORSSerialPortsWereDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPorts()
            }
        }
    }
}
