import SwiftUI

struct StatusChipsView: View {
    @Environment(AmplifierViewModel.self) private var vm

    /// Expand the amp's single-letter power level code to the human-
    /// readable label shown on the status chip.
    static func levelLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "L": return "LOW"
        case "M": return "MED"
        case "H": return "HIGH"
        default:  return code.isEmpty ? "—" : code
        }
    }

    var body: some View {
        // Single row of equal-width chips, compact sizing so 7 fit without
        // wrapping on the narrow window layout.
        //
        // When the amp is unresponsive (`!vm.isAmpResponding`) every
        // CSV-derived field is stale — show `—` and a muted accent so
        // we don't lie about band / antenna / TX state. CAT is cached
        // from the amp's own config screen and survives a power cycle,
        // so it stays as-is.
        let alive = vm.isAmpResponding
        let dashed = "—"
        let mutedAccent: Color = Color(white: 0.35)

        HStack(spacing: 3) {
            StatusChip(
                label: "STATUS",
                value: alive ? vm.state.txStatus : dashed,
                accent: alive ? (vm.state.txStatus == "TX" ? .red : .green)
                              : mutedAccent,
                compact: true
            )
            StatusChip(
                label: "BAND",
                value: alive ? vm.state.band : dashed,
                accent: alive ? .cyan : mutedAccent,
                onTap: alive ? { vm.sendCommand(.bandUp) } : nil,
                onLongPress: alive ? { vm.sendCommand(.bandDown) } : nil,
                compact: true
            )
            StatusChip(
                label: "ANT",
                value: alive ? vm.txAntennaWithSuffix : dashed,
                accent: alive ? .cyan : mutedAccent,
                onTap: alive ? { vm.sendCommand(.antenna) } : nil,
                compact: true
            )
            StatusChip(
                label: "IN",
                value: alive ? vm.state.input : dashed,
                accent: alive ? .cyan : mutedAccent,
                onTap: alive ? { vm.sendCommand(.input) } : nil,
                compact: true
            )
            StatusChip(
                label: "LEVEL",
                value: alive ? Self.levelLabel(vm.state.pLevel) : dashed,
                accent: alive ? .cyan : mutedAccent,
                onTap: alive ? { vm.sendCommand(.power) } : nil,
                compact: true
            )
            StatusChip(
                label: "MODE",
                value: alive ? (vm.state.opStatus == "Oper" ? "OPER" : "STBY")
                             : dashed,
                accent: alive ? (vm.state.opStatus == "Oper" ? .orange : .gray)
                              : mutedAccent,
                onTap: alive ? { vm.sendCommand(.operate) } : nil,
                compact: true
            )
            StatusChip(
                label: "CAT",
                value: vm.cachedCatType.isEmpty ? "—" : vm.cachedCatType,
                accent: alive ? .cyan : mutedAccent,
                compact: true
            )
        }
    }
}

struct StatusChip: View {
    let label: String
    let value: String
    var accent: Color = .cyan
    var onTap: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    /// Smaller font/padding for a 7-across chip row. Default is the older
    /// roomy style; pass `compact: true` when chips need to fit tight.
    var compact: Bool = false

    private var isTappable: Bool { onTap != nil }
    private var labelSize: CGFloat { compact ? 7   : 8 }
    private var valueSize: CGFloat { compact ? 11  : 13 }
    private var chevronSize: CGFloat { compact ? 5 : 6 }
    private var vPadding:  CGFloat { compact ? 4   : 6 }

    var body: some View {
        VStack(spacing: compact ? 1 : 2) {
            Text(label)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .tracking(0.5)
                .lineLimit(1)
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if isTappable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: chevronSize))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        // Padding first, then maxWidth: .infinity — so every chip in the
        // HStack receives the same proposed width regardless of content.
        .padding(.vertical, vPadding)
        .padding(.horizontal, compact ? 2 : 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(accent.opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onLongPressGesture {
            onLongPress?()
        }
    }
}
