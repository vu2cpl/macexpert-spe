import Foundation

/// Connection mode selection
enum ConnectionMode: String, CaseIterable {
    case serial = "Serial"
    case websocket = "WebSocket"
}

/// Protocol for amplifier connections (serial or WebSocket).
@MainActor
protocol ConnectionProvider: AnyObject {
    var isConnected: Bool { get }
    var onStateUpdate: ((AmplifierState) -> Void)? { get set }
    var onConnectionChange: ((Bool) -> Void)? { get set }

    func connect() async throws
    func disconnect()
    func sendCommand(_ command: SPECommand)
}
