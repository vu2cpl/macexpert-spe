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

    /// Fires for each raw RCU display packet received from the amp (bytes
    /// after the `AA AA AA 6A` sync+marker, no trailing checksum). Emitted
    /// by both transports: the serial handler parses it off the byte stream
    /// locally, and the WebSocket connection receives it as a binary message
    /// forwarded by spe-remote.
    var onRCUDisplayPacket: ((Data) -> Void)? { get set }

    /// Fires with every chunk of bytes read off the wire, before any parsing.
    /// Used by the capture pipeline's raw sidecar log for ground-truth
    /// diagnostics. Optional; serial-only today.
    var onRawBytes: ((Data) -> Void)? { get set }

    /// Fires each time a fresh RCU frame round-trip completes — on serial
    /// that's the local OFF→ON ticker, on WebSocket it's every received
    /// binary message. Either way the debug overlay uses this to show the
    /// RCU pipeline is alive.
    var onRCUTick: (() -> Void)? { get set }

    func connect() async throws
    func disconnect()
    func sendCommand(_ command: SPECommand)
    func powerOn() async
}
