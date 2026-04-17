import Foundation

/// Parser helper for the SPE 1.5K-FA proprietary LCD display packet streamed
/// in RCU mode. Identified by type byte `0x6A` immediately after the standard
/// `AA AA AA` sync.
///
/// IMPORTANT: empirically (raw capture, 2026-04-16) the frame is **NOT** 106
/// bytes — that interpretation of `0x6A` as a length was wrong. `0x6A` is just
/// a packet *type* marker; the actual frame is several hundred bytes and ends
/// only when the next sync pattern arrives (or a quiet period). The frame
/// embeds visible LCD text with attribute bits set on some characters
/// (e.g. "STANDBY" appears as `33 54 41 4E 44 42 59` = "3TANDBY", with bit 5
/// of the 'S' cleared as an attribute flag).
///
/// This helper uses **sync-to-sync framing**: it locates `AA AA AA 6A`, then
/// scans forward for the next `AA AA AA` to determine the frame end. Returns
/// nil if no terminating sync is yet in the buffer (caller should wait for
/// more bytes).
enum RCUDisplayPacket {
    /// Type byte that marks an LCD display frame.
    static let typeMarker: UInt8 = 0x6A

    /// Maximum bytes we'll buffer waiting for a closing sync before giving up
    /// and flushing what we have. Observed 1.5K-FA frame is ~371 bytes; 512
    /// leaves headroom but flushes promptly when no follow-on frame arrives.
    static let maxFrameBytes = 512

    /// Locate the first complete `AA AA AA 6A …` frame in `data`.
    /// The frame ends just before the next `AA AA AA` sync (whether that's
    /// another 0x6A frame or a CSV 0x43 frame).
    ///
    /// Returns `(range, dataBytes)` where `range` covers the entire frame on
    /// the wire (sync byte through last byte before next sync) and
    /// `dataBytes` are the bytes after the `6A` type marker.
    ///
    /// Returns nil if no opening sync is found, or an opening sync is found
    /// but no closing sync has arrived yet.
    static func find(in data: Data) -> (range: Range<Int>, dataBytes: [UInt8])? {
        // Locate `AA AA AA 6A` opening.
        guard let start = findSync(in: data, type: typeMarker, from: 0) else {
            return nil
        }

        let dataStart = start + 4

        // Look for the next `AA AA AA` after the opening, of any type.
        if let nextSync = findAnySync(in: data, from: dataStart) {
            let dataSlice = Array(data[dataStart..<nextSync])
            return (range: start..<nextSync, dataBytes: dataSlice)
        }

        // No closing sync yet. If the buffer has grown beyond reason, flush
        // what we have so the receive loop doesn't stall forever.
        if data.count - start >= maxFrameBytes {
            let dataSlice = Array(data[dataStart..<data.count])
            return (range: start..<data.count, dataBytes: dataSlice)
        }

        return nil
    }

    private static func findSync(in data: Data, type: UInt8, from offset: Int) -> Int? {
        guard data.count >= offset + 4 else { return nil }
        for i in offset...(data.count - 4) {
            if data[i] == 0xAA, data[i+1] == 0xAA, data[i+2] == 0xAA, data[i+3] == type {
                return i
            }
        }
        return nil
    }

    private static func findAnySync(in data: Data, from offset: Int) -> Int? {
        guard data.count >= offset + 3 else { return nil }
        for i in offset...(data.count - 3) {
            if data[i] == 0xAA, data[i+1] == 0xAA, data[i+2] == 0xAA {
                return i
            }
        }
        return nil
    }
}
