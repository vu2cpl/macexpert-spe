import Foundation

/// Attribute-aware decoder for the SPE 1.5K-FA proprietary LCD byte stream.
///
/// Each byte on the LCD is a character with optional "highlighted/inverse"
/// attribute:
///   - 0x10-0x3F: attributed char. Real ASCII = byte + 0x20.
///                (e.g. 0x33 -> 0x53 = 'S', 0x11 -> 0x31 = '1')
///   - 0x40-0x7E: normal ASCII.
///   - 0x00:      null / empty cell.
///   - anything else: custom LCD glyph (separators, icons) — we replace with
///     a dot so searches and rendering still align.
enum LCDText {
    /// Decode a slice of LCD bytes into a string, substituting '.' for any
    /// byte we can't map to printable ASCII. Preserves byte-to-character
    /// alignment so byte offsets stay meaningful.
    static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes.map(decodeChar))
    }

    /// Convenience: decode from an array with the same semantics.
    static func decode(_ bytes: [UInt8]) -> String {
        decode(bytes[...])
    }

    /// Decode and compress: collapse runs of '.' (unprintables/nulls) into
    /// single spaces, trim leading/trailing whitespace. Useful for headers
    /// and help strings where spacing is LCD-layout noise.
    static func decodeTrimmed(_ bytes: ArraySlice<UInt8>) -> String {
        let raw = decode(bytes)
        // Replace runs of '.' with a single space.
        var out = ""
        var lastWasDot = false
        for ch in raw {
            if ch == "." {
                if !lastWasDot { out.append(" ") }
                lastWasDot = true
            } else {
                out.append(ch)
                lastWasDot = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Case-insensitive substring check against the decoded string. Used for
    /// screen detection (matching header text) and overlay detection.
    static func contains(_ bytes: ArraySlice<UInt8>, text: String) -> Bool {
        decode(bytes).lowercased().contains(text.lowercased())
    }

    // MARK: - Private

    private static func decodeChar(_ b: UInt8) -> Character {
        if b >= 0x10 && b <= 0x3F {
            // Attributed: toggle bit 5 to get real ASCII.
            return Character(UnicodeScalar(b + 0x20))
        }
        if b >= 0x40 && b <= 0x7E {
            return Character(UnicodeScalar(b))
        }
        return "."
    }
}
