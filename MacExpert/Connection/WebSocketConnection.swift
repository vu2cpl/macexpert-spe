import Foundation

/// WebSocket connection to the spe-remote server.
@MainActor
final class WebSocketConnection: NSObject, ConnectionProvider, @unchecked Sendable {
    var isConnected: Bool = false
    var onStateUpdate: ((AmplifierState) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    /// Fired when spe-remote forwards a 0x6A RCU LCD display frame as a
    /// binary WebSocket message. Payload matches what the serial path
    /// delivers — bytes after the `AA AA AA 6A` sync+marker — so the same
    /// RCUFrame parser works on both transports.
    var onRCUDisplayPacket: ((Data) -> Void)?
    /// Not currently emitted — raw byte stream isn't exposed by spe-remote.
    var onRawBytes: ((Data) -> Void)?
    /// Fired each time an RCU frame arrives. Lets the debug overlay count
    /// frames even though we aren't driving the OFF→ON ticker locally (the
    /// Pi server does that on our behalf).
    var onRCUTick: (() -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var url: URL
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = false
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 16.0

    init(url: URL) {
        self.url = url
        super.init()
    }

    func configure(url: URL) {
        self.url = url
    }

    func connect() async throws {
        shouldReconnect = true
        reconnectDelay = 1.0

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)

        guard let ws = session?.webSocketTask(with: url) else {
            throw ConnectionError.websocketFailed("Failed to create WebSocket task")
        }

        webSocketTask = ws
        ws.resume()

        isConnected = true
        onConnectionChange?(true)
        reconnectDelay = 1.0

        startReceiving()
    }

    func disconnect() {
        shouldReconnect = false
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        onConnectionChange?(false)
    }

    func sendCommand(_ command: SPECommand) {
        guard let ws = webSocketTask else { return }

        let message: String
        switch command {
        case .status:
            // In WebSocket mode, server pushes state — no explicit status request needed
            return
        default:
            message = command.wsCommandName
        }

        ws.send(.string(message)) { error in
            if let error {
                print("WebSocket send error: \(error.localizedDescription)")
            }
        }
    }

    func powerOn() async {
        sendRawCommand("power_on")
    }

    /// Send a raw string command (for power_on which isn't in SPECommand).
    func sendRawCommand(_ command: String) {
        guard let ws = webSocketTask else { return }
        ws.send(.string(command)) { error in
            if let error {
                print("WebSocket send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let ws = webSocketTask else { break }

            do {
                let message = try await ws.receive()
                await handleMessage(message)
            } catch {
                await handleDisconnect()
                break
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            do {
                let decoder = JSONDecoder()
                let state = try decoder.decode(AmplifierState.self, from: data)
                await MainActor.run {
                    onStateUpdate?(state)
                }
            } catch {
                // Might be a power_result or other JSON
                print("JSON decode note: \(error.localizedDescription)")
            }
        case .data(let data):
            // spe-remote sends RCU LCD frames as binary messages (the bytes
            // after AA AA AA 6A). Anything else binary-shaped is unexpected
            // but treat the same way — RCUFrame.parse will bail gracefully
            // if the payload doesn't look right.
            await MainActor.run {
                onRCUDisplayPacket?(data)
                onRCUTick?()
            }
        @unknown default:
            break
        }
    }

    private func handleDisconnect() async {
        await MainActor.run {
            isConnected = false
            onConnectionChange?(false)
        }

        guard shouldReconnect else { return }

        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(reconnectDelay))

            guard !Task.isCancelled, shouldReconnect else { return }

            await MainActor.run {
                reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
            }

            do {
                try await connect()
            } catch {
                print("Reconnect failed: \(error.localizedDescription)")
            }
        }
    }
}
