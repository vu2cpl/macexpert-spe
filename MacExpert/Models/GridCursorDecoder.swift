import Foundation

/// Decoders for the SPE 1.5K-FA grid-menu cursor position, which lives at
/// bytes 325-364 of the 367-byte RCU frame.
///
/// Encoding scheme (consistent across all grid menus):
///   - The cursor area is split into N "column bands" — one contiguous byte
///     range per on-screen column.
///   - Within the active column's band, exactly one byte is non-zero. Its
///     value is a bit flag identifying the row:
///       0x02 = row 0, 0x04 = row 1, 0x08 = row 2, 0x10 = row 3.
///   - Some sub-menus introduce additional bits (e.g. 0x20 for a SAVE button).
///
/// Each per-menu helper returns a navigation index matching the order the
/// app's view model uses (typically column-first). Nil when no cursor is
/// visible (e.g. frame isn't a grid menu, or cursor scheme doesn't match).
enum GridCursorDecoder {

    // MARK: - Bit-flag helpers

    /// Scan a byte range and return `(row, bit)` for the first non-zero byte,
    /// where row is derived from a bit flag:
    ///   0x02 -> row 0, 0x04 -> row 1, 0x08 -> row 2, 0x10 -> row 3,
    ///   0x20 -> row 4 (seen as SAVE marker in CONFIG).
    /// Returns nil if no recognized bit is set in the range.
    static func rowBit(in bytes: [UInt8], range: Range<Int>) -> Int? {
        for i in range where i < bytes.count {
            let v = bytes[i]
            if v == 0 { continue }
            switch v {
            case 0x02: return 0
            case 0x04: return 1
            case 0x08: return 2
            case 0x10: return 3
            case 0x20: return 4
            default:
                // Unrecognized but non-zero — skip; not all captures have
                // perfectly clean cursor bytes.
                continue
            }
        }
        return nil
    }

    // MARK: - SETUP root (4x3 grid, nav order column-first)
    //
    //   col 1 (325-337): CONFIG(0), ANTENNA(1), CAT(2), MANUAL TUNE(3)
    //   col 2 (339-352): DISPLAY(4), BEEP(5), START(6), TEMP FANS(7)
    //   col 3 (353-364): ALARMS LOG(8), TUN ANT(9), RX ANT(10), EXIT(11)

    static func decodeSetupRootCursor(_ bytes: [UInt8]) -> Int? {
        if let row = rowBit(in: bytes, range: 325..<338) { return row }
        if let row = rowBit(in: bytes, range: 339..<353) { return 4 + row }
        if let row = rowBit(in: bytes, range: 353..<365) { return 8 + row }
        return nil
    }

    // MARK: - CAT menu (3x3 grid, nav order column-first)
    //
    //   col 1 (325-333): NONE(0), ICOM(1), KENWOOD(2)
    //   col 2 (338-349): YAESU(3), TEN-TEC(4), FLEX-RADIO(5)
    //   col 3 (351-361): ELECRAFT(6), BAND DATA(7), EXIT(8)
    //
    // The view model's CATSubMenuView.navToGrid matches this ordering.

    static func decodeCATCursor(_ bytes: [UInt8]) -> Int? {
        if let row = rowBit(in: bytes, range: 325..<334) { return row }
        if let row = rowBit(in: bytes, range: 338..<350) { return 3 + row }
        if let row = rowBit(in: bytes, range: 351..<362) { return 6 + row }
        return nil
    }

    // MARK: - CONFIG sub-menu ("OTHER SETTINGS")
    //
    // Non-rectangular layout; row 0 is skipped in both columns, and SAVE uses
    // bit 0x20 in a narrow range. Nav order matches the view's nav model:
    //   BNK A(0), BNK B(1), REMOTE ANT(2), SO2R(3), COMBINER(4), SAVE(5).

    static func decodeConfigCursor(_ bytes: [UInt8]) -> Int? {
        // Check SAVE first (bit 0x20 in the tail range). SAVE is special: the
        // 0x20 bits appear starting around 358 rather than in a clean column.
        if bytes.count > 363, (358...363).contains(where: { bytes[$0] == 0x20 }) {
            return 5
        }
        // Col 1 = BNK A (bit 0x04) / BNK B (bit 0x08). Range 326-337.
        if let bit = firstBit(in: bytes, range: 326..<338) {
            switch bit {
            case 0x04: return 0  // BNK A
            case 0x08: return 1  // BNK B
            default: break
            }
        }
        // Col 2 = REMOTE ANT (0x04), SO2R (0x08), COMBINER (0x10). Range 341-358.
        if let bit = firstBit(in: bytes, range: 341..<358) {
            switch bit {
            case 0x04: return 2  // REMOTE ANT SWITCH
            case 0x08: return 3  // SO2R MATRIX
            case 0x10: return 4  // COMBINER
            default: break
            }
        }
        return nil
    }

    // MARK: - Single-column sub-menus (TEMP/FANS, RX ANT, TUN ANT)
    //
    // These menus list items stacked vertically — conceptually a single
    // column. We assume the cursor uses the same bit-flag scheme in the
    // first column band (325-337) that SETUP root uses for its left
    // column. Not verified empirically for all of these — if a cursor
    // read misbehaves, we may need per-menu decoders.

    /// TEMP/FANS has 3 items: TEMP SCALE(0), FAN MGMT(1), SAVE(2).
    ///
    /// Encoding is different from SETUP root — the bit values start at
    /// `0x04` (not `0x02`), and SAVE uses `0x10` in a separate byte range.
    /// Verified from capture 2026-04-17:
    ///   TEMP SCALE: `0x04` in bytes 325-344
    ///   FAN MGMT:   `0x08` in bytes 325-344
    ///   SAVE:       `0x10` in bytes 345-364
    static func decodeTempFansCursor(_ bytes: [UInt8]) -> Int? {
        if let bit = firstBit(in: bytes, range: 325..<345) {
            switch bit {
            case 0x04: return 0  // TEMP SCALE
            case 0x08: return 1  // FAN MGMT
            default: break
            }
        }
        if let bit = firstBit(in: bytes, range: 345..<365) {
            if bit == 0x10 { return 2 }  // SAVE
        }
        return nil
    }

    /// RX ANT has 4 items: ANT2(0), ANT3(1), ANT4(2), SAVE(3).
    ///
    /// Same bit-flag encoding as TEMP/FANS — bits start at `0x04`, SAVE
    /// uses `0x10` in the 345-364 range. Verified from capture 2026-04-17.
    static func decodeRxAntCursor(_ bytes: [UInt8]) -> Int? {
        if let bit = firstBit(in: bytes, range: 325..<345) {
            switch bit {
            case 0x04: return 0  // ANT2
            case 0x08: return 1  // ANT3
            case 0x10: return 2  // ANT4
            default: break
            }
        }
        if let bit = firstBit(in: bytes, range: 345..<365) {
            if bit == 0x10 { return 3 }  // SAVE
        }
        return nil
    }

    /// TUN ANT has 6 items: ANT1(0), ANT2(1), ANT3(2), ANT4(3), PORT(4), SAVE(5).
    ///
    /// The LCD shows a 2x3 grid:
    ///     row 0:  ANT1    ANT3    PORT
    ///     row 1:  ANT2    ANT4    SAVE
    /// Each cell's cursor is encoded by its starting byte position (column)
    /// + bit value (row). Verified end-to-end from captures 2026-04-17:
    ///
    ///   Column     Start byte   Row 0 bit   Row 1 bit
    ///   col 1      325-340      0x04 ANT1   0x08 ANT2
    ///   col 2      341-345      0x04 ANT3   0x08 ANT4
    ///   col 3      346-355      0x04 PORT   (nothing)
    ///   col 3bis   356-361      (nothing)   0x10 SAVE
    static func decodeTunAntCursor(_ bytes: [UInt8]) -> Int? {
        guard bytes.count > 362 else { return nil }
        // Find the first non-zero byte anywhere in the cursor region.
        guard let startIdx = (325..<365).first(where: { bytes[$0] != 0 }) else {
            return nil
        }
        let bit = bytes[startIdx]

        if startIdx < 341 {
            switch bit {
            case 0x04: return 0   // ANT1
            case 0x08: return 1   // ANT2
            default: return nil
            }
        } else if startIdx < 346 {
            switch bit {
            case 0x04: return 2   // ANT3
            case 0x08: return 3   // ANT4
            default: return nil
            }
        } else if startIdx < 356 {
            if bit == 0x04 { return 4 }   // PORT
        } else {
            if bit == 0x10 { return 5 }   // SAVE
        }
        return nil
    }

    // MARK: - YAESU model picker (14 items, 5+5+4 column layout)
    //
    // Nav order (column-first through the 14 Yaesu models):
    //   Col 1 (5 items):  0=FT100, 1=FT757 GX2, 2=FT817/847, 3=FT840/890, 4=FT897
    //   Col 2 (5 items):  5=FT900, 6=FT920, 7=FT990, 8=FT1000, 9=FT1000 MP1
    //   Col 3 (4 items): 10=FT1000 MP2, 11=FT1000 MP3, 12=FTXXX 2007+, 13=FT991
    //
    // Cursor bytes use the same bit-flag scheme as SETUP root, with one
    // extra row (bit 0x20 = row 4) in columns that have 5 items. Byte
    // ranges mirror SETUP root's layout by default; will be tightened
    // once confirmed from live captures.

    static func decodeYaesuModelCursor(_ bytes: [UInt8]) -> Int? {
        // Verified from capture 2026-04-17: each column is a tightly-packed
        // 13-byte range with no overlap between neighbors. My earlier guess
        // had col 2 ending at byte 352, overlapping col 3 at byte 351 —
        // that caused FT991 (col 3 row 3) to be decoded as FT1000 (col 2
        // row 3).
        //
        //   Column 1 (5 rows): bytes 325-337, bits 0x02/0x04/0x08/0x10/0x20
        //   Column 2 (5 rows): bytes 338-350, bits 0x02/0x04/0x08/0x10/0x20
        //   Column 3 (4 rows): bytes 351-363, bits 0x02/0x04/0x08/0x10
        if let row = extendedRowBit(in: bytes, range: 325..<338, maxRow: 4) {
            return row
        }
        if let row = extendedRowBit(in: bytes, range: 338..<351, maxRow: 4) {
            return 5 + row
        }
        if let row = extendedRowBit(in: bytes, range: 351..<364, maxRow: 3) {
            return 10 + row
        }
        return nil
    }

    // MARK: - TEN-TEC model picker (4 items, 2×2 grid)
    //
    // Verified 2026-04-17 via live amp walkthrough. Each cell has its own
    // (byte range, bit) pair; nav order is column-first (OMNI → ORION →
    // JUPITER → ARGONAUT, wrapping back to OMNI).
    //
    //   Model           Byte range   Bit
    //   OMNI VII (0)    332-343      0x04
    //   ORION I/II (1)  332-343      0x08
    //   JUPITER (2)     345-356      0x04
    //   ARGONAUT V (3)  345-356      0x08
    //
    // Layout:
    //   OMNI VII   | JUPITER
    //   ORION I/II | ARGONAUT V

    static func decodeTenTecModelCursor(_ bytes: [UInt8]) -> Int? {
        // Column 1: OMNI VII / ORION I/II
        if let bit = firstBit(in: bytes, range: 332..<344) {
            switch bit {
            case 0x04: return 0   // OMNI VII
            case 0x08: return 1   // ORION I/II
            default: break
            }
        }
        // Column 2: JUPITER / ARGONAUT V
        if let bit = firstBit(in: bytes, range: 345..<357) {
            switch bit {
            case 0x04: return 2   // JUPITER
            case 0x08: return 3   // ARGONAUT V
            default: break
            }
        }
        return nil
    }

    // MARK: - CAT Baud Rate picker (8 items, 4×2 grid)
    //
    // Same screen for all CAT types. The right half of the LCD is a 4×2
    // grid of standard speeds:
    //   Col 1 (rows 0-3): 1200, 2400, 4800, 9600
    //   Col 2 (rows 0-3): 19200, 38400, 57600, 115200
    //
    // Column byte ranges verified from YAESU captures 2026-04-16. Same
    // bit-flag scheme: 0x02/0x04/0x08/0x10 for rows 0-3.

    static func decodeBaudRateCursor(_ bytes: [UInt8]) -> Int? {
        // Column 1: bytes 338-353, rows 0-3 = 1200 / 2400 / 4800 / 9600.
        if let row = rowBit(in: bytes, range: 338..<354) {
            return row
        }
        // Column 2: bytes 354-363, rows 0-3 = 19200 / 38400 / 57600 / 115200.
        if let row = rowBit(in: bytes, range: 354..<364) {
            return 4 + row
        }
        return nil
    }

    /// TUN ANT → PORT nested screen. Layout:
    ///   left half: PROTOCOL / DATA BIT / STOP BIT / PARITY
    ///   right half: 4×2 baud grid (same as CAT baud)
    ///
    /// Cursor encoding (confirmed for col 1 via 1200 capture, mirror-
    /// assumed for col 2):
    ///   Col 1 (1200/2400/4800/9600):     bytes 345-353, ascending bits.
    ///   Col 2 (19200/38400/57600/115200): bytes 354-363, ascending bits.
    /// Nav index: 0-3 = col 1, 4-7 = col 2. Left-side fields (PROTOCOL…)
    /// cursor encoding TBD — returns nil if cursor is on those.
    static func decodeTunAntPortCursor(_ bytes: [UInt8]) -> Int? {
        // Col 1 spans bytes 346-352; col 2 spans 353-361. They overlap at
        // byte 353 in raw captures because the cursor "stripe" is 8-9 bytes
        // wide and drifts by one between columns, so we bound col 1 before
        // 353 and start col 2 at 353 — disambiguating by whichever side has
        // the set bit.
        if let r = rowBit(in: bytes, range: 345..<353) { return r }
        if let r = rowBit(in: bytes, range: 353..<363) { return 4 + r }
        return nil
    }

    /// Like `rowBit` but supports rows up to `maxRow` via bits 0x02..0x80.
    /// Used by screens with more than 4 rows per column (e.g. YAESU
    /// model picker has 5 rows in columns 1-2).
    static func extendedRowBit(in bytes: [UInt8], range: Range<Int>, maxRow: Int = 6) -> Int? {
        for i in range where i < bytes.count {
            let v = bytes[i]
            if v == 0 { continue }
            let row: Int
            switch v {
            case 0x02: row = 0
            case 0x04: row = 1
            case 0x08: row = 2
            case 0x10: row = 3
            case 0x20: row = 4
            case 0x40: row = 5
            case 0x80: row = 6
            default: continue
            }
            if row <= maxRow { return row }
        }
        return nil
    }

    // MARK: - Private

    /// Scan a byte range, return the first non-zero byte value.
    private static func firstBit(in bytes: [UInt8], range: Range<Int>) -> UInt8? {
        for i in range where i < bytes.count {
            if bytes[i] != 0 { return bytes[i] }
        }
        return nil
    }
}
