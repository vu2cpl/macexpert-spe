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

    /// Fires for each raw RCU display packet received from the amp (CNT = 0x6A
    /// data bytes only, no sync/length/checksum). Optional; serial-only today.
    var onRCUDisplayPacket: ((Data) -> Void)? { get set }

    /// Fires with every chunk of bytes read off the wire, before any parsing.
    /// Used by the capture pipeline's raw sidecar log for ground-truth
    /// diagnostics. Optional; serial-only today.
    var onRawBytes: ((Data) -> Void)? { get set }

    /// Fires each time the RCU polling ticker completes an OFF→ON cycle.
    /// Optional; serial-only today.
    var onRCUTick: (() -> Void)? { get set }

    func connect() async throws
    func disconnect()
    func sendCommand(_ command: SPECommand)
    func powerOn() async
}
