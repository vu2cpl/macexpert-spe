import SwiftUI

/// Collapsible debug overlay showing the fields decoded from the most recent
/// RCU display frame. Shown only while in SETUP mode (where RCU is active).
///
/// Intended for diagnosing parser issues during development — things like
/// "are we seeing frames for this screen?", "what does the cursor byte range
/// say?", and "do the checkbox state bytes match what's actually on screen?".
struct RCUDebugView: View {
    @Environment(AmplifierViewModel.self) private var vm
    @State private var isExpanded = true

    var body: some View {
        let frame = vm.rcuFrame

        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "ladybug")
                        .foregroundStyle(.yellow)
                    Text("RCU Parser Debug")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(frame == nil ? "no frame yet" : frame!.screen.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    // Connection + pipeline state, always visible.
                    row("connection", vm.connectionMode.rawValue)
                    row("rcuOwner",   vm.rcuOwner.rawValue)
                    row("ticksSent",  "\(vm.rcuTicksSent)")
                    row("callbacks",  "\(vm.rcuCallbackCount)  (last: \(ageString(vm.rcuLastCallbackAt)))")
                    row("parsed",     "\(vm.rcuFrameCount)")

                    Divider().padding(.vertical, 2)

                    if let f = frame {
                        row("screen",     f.screen.rawValue)
                        row("header",     quote(f.header))
                        row("footer",     quote(f.footer))
                        row("bankLetter", f.bankLetter.map { String($0) } ?? "—")
                        row("gridCursor", f.gridCursorNavIndex.map { String($0) } ?? "—")
                        // Raw cursor byte region (325-364) — useful for
                        // building per-menu cursor decoders. Split across
                        // two rows so it doesn't overflow the panel.
                        row("cur 325-344", hexDump(bytes: f.raw, range: 325..<345))
                        row("cur 345-364", hexDump(bytes: f.raw, range: 345..<365))
                        if f.screen == .yaesuModel || f.screen == .tenTecModel || f.screen == .baudRate {
                            row("cursor hits", cursorHits(bytes: f.raw, range: 325..<365))
                        }
                        if f.screen == .tunAntPort {
                            row("proto",    f.tunAntPortProtocol ?? "— (nil)")
                            row("data bit", f.tunAntPortDataBit  ?? "— (nil)")
                            row("stop bit", f.tunAntPortStopBit  ?? "— (nil)")
                            row("parity",   f.tunAntPortParity   ?? "— (nil)")
                            row("tp scan 0-191", quote(decodeRegion(bytes: f.raw, range: 0..<192)))
                        }
                        if f.screen == .baudRate {
                            row("br cat",   f.baudRateCatType ?? "— (nil)")
                            row("br model", f.baudRateModel   ?? "— (nil)")
                            row("br scan 0-127", quote(decodeRegion(bytes: f.raw, range: 0..<128)))
                            row("br hex 32-63",  hexDump(bytes: f.raw, range: 32..<64))
                            row("br hex 64-95",  hexDump(bytes: f.raw, range: 64..<96))
                            row("br hex 96-127", hexDump(bytes: f.raw, range: 96..<128))
                        }

                        if f.screen == .antennaMatrix {
                            row("ant cursor band", f.antennaCursorBand ?? "— (parse failed)")
                            row("ant cursor slot1", f.antennaCursorSlot1 ?? "— (parse failed)")
                            row("slot 52-55", hexDump(bytes: f.raw, range: 52..<56))
                            row("map size", "\(vm.antennaMatrix.count) / 11")
                            row("map keys", sortedKeys(vm.antennaMatrix))
                        }

                        if f.screen == .display {
                            let blCaps = capSummary(bytes: f.raw, range: RCUFrame.backlightRange)
                            let crCaps = capSummary(bytes: f.raw, range: RCUFrame.contrastRange)
                            row("backlight",
                                "\(f.backlightLevel.map(String.init) ?? "—") / \(RCUFrame.barLevelMax)   \(blCaps)")
                            row("bl bytes",
                                hexDump(bytes: f.raw, range: RCUFrame.backlightRange))
                            row("contrast",
                                "\(f.contrastLevel.map(String.init) ?? "—") / \(RCUFrame.barLevelMax)   \(crCaps)")
                            row("cr bytes",
                                hexDump(bytes: f.raw, range: RCUFrame.contrastRange))
                        }
                        if let cfg = f.configState {
                            row("configState", "A=\(cfg.bankA.i) B=\(cfg.bankB.i) R=\(cfg.remoteAntSwitch.i) S=\(cfg.so2rMatrix.i) C=\(cfg.combiner.i)")
                        }
                        if f.antennaNotAvailable {
                            row("overlay", "ANTENNA NOT AVAILABLE")
                        }
                        if let band = f.currentBandLabel {
                            row("band",    band)
                        }
                        if let ant = f.currentAntenna {
                            row("antenna", "\(ant)")
                        }
                    } else {
                        Text("Waiting for RCU frame — no 0x6A frames seen yet.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button("Sync Now") { vm.syncFromAmp() }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                            .disabled(!vm.isConnected || vm.connectionMode != .serial)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer()
        }
    }

    private func quote(_ s: String) -> String {
        s.isEmpty ? "—" : "\"\(s)\""
    }

    private func ageString(_ date: Date?) -> String {
        guard let date else { return "never" }
        let age = Date().timeIntervalSince(date)
        if age < 1 { return "now" }
        if age < 60 { return String(format: "%.0fs ago", age) }
        return String(format: "%.0fm ago", age / 60)
    }

    /// Decode a byte range using the LCD attribute decoder — used so the
    /// debug view can show what the parser is actually scanning.
    private func decodeRegion(bytes: [UInt8], range: Range<Int>) -> String {
        guard range.upperBound <= bytes.count else { return "(too short)" }
        return LCDText.decodeTrimmed(bytes[range])
    }

    private func hexDump(bytes: [UInt8], range: Range<Int>) -> String {
        guard range.upperBound <= bytes.count else { return "(too short)" }
        return range.map { String(format: "%02X", bytes[$0]) }.joined(separator: " ")
    }

    /// Summary of every non-zero byte in the cursor region — "byte=value"
    /// pairs, grouped into runs. Compact form: "337..349=02" means bytes
    /// 337 through 349 are all 0x02.
    private func cursorHits(bytes: [UInt8], range: Range<Int>) -> String {
        guard range.upperBound <= bytes.count else { return "(too short)" }
        var runs: [(Int, Int, UInt8)] = []  // (startByte, endByte, value)
        var current: (start: Int, value: UInt8)? = nil
        for i in range {
            let v = bytes[i]
            if v == 0 {
                if let c = current {
                    runs.append((c.start, i - 1, c.value))
                    current = nil
                }
            } else if let c = current, c.value == v {
                // Still in run
            } else {
                if let c = current {
                    runs.append((c.start, i - 1, c.value))
                }
                current = (i, v)
            }
        }
        if let c = current {
            runs.append((c.start, range.upperBound - 1, c.value))
        }
        if runs.isEmpty { return "(no cursor bits)" }
        return runs.map { "\($0.0)..\($0.1)=\(String(format: "%02X", $0.2))" }.joined(separator: ", ")
    }

    /// Comma-separated list of map keys (sorted), shortened so the debug
    /// row doesn't overflow.
    private func sortedKeys<V>(_ map: [String: V]) -> String {
        let keys = map.keys.sorted()
        let joined = keys.joined(separator: ", ")
        return joined.isEmpty ? "(empty)" : joined
    }

    /// "L=92 R=98" — first and last non-0x93 bytes in the bar range.
    private func capSummary(bytes: [UInt8], range: Range<Int>) -> String {
        guard range.upperBound <= bytes.count else { return "" }
        let slice = Array(bytes[range])
        let left = slice.first { $0 != 0x93 }
        let right = slice.reversed().first { $0 != 0x93 }
        let l = left.map { String(format: "%02X", $0) } ?? "—"
        let r = right.map { String(format: "%02X", $0) } ?? "—"
        return "L=\(l) R=\(r)"
    }
}

private extension Bool {
    var i: String { self ? "1" : "0" }
}
