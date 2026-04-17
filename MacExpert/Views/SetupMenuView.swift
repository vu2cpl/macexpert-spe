import SwiftUI

struct SetupMenuView: View {
    @Environment(AmplifierViewModel.self) private var vm

    /// Grid labels in display order (row-major: left to right, top to bottom)
    private let gridLabels: [[String]] = [
        ["CONFIG", "DISPLAY", "ALARMS LOG"],
        ["ANTENNA", "BEEP", "TUN ANT"],
        ["CAT", "START", "RX ANT"],
        ["MANUAL TUNE", "TEMP/FANS", "EXIT"],
    ]

    /// Convert grid (row, col) to navigation index
    private func navIndexFor(row: Int, col: Int) -> Int? {
        AmplifierViewModel.setupNavToGrid.firstIndex(where: { $0.row == row && $0.col == col })
    }

    var body: some View {
        let cursorIndex = vm.setupCursorIndex
        let cursorPos = cursorIndex < AmplifierViewModel.setupNavToGrid.count
            ? AmplifierViewModel.setupNavToGrid[cursorIndex]
            : (row: -1, col: -1)

        LCDContainer(
            title: "SETUP OPTIONS",
            subtitle: "vs. INPUT \(vm.state.input)",
            hintLeft: "[\u{25C0}\u{25B6}]: SELECT",
            hintRight: "[SET]: CONFIRM"
        ) {
            // Fill the LCDContainer body. Each cell stretches equally
            // (maxHeight: .infinity on the row wrappers), bigger font so
            // touch targets are generous on the one menu everyone hits
            // first.
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { col in
                            let label = gridLabels[row][col]
                            let isSelected = cursorPos.row == row && cursorPos.col == col
                            cell(label: label, isSelected: isSelected)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    /// A single grid cell. BEEP and START append their current toggle
    /// state to the right of the label (e.g. `BEEP  ON`, `START STBY`).
    @ViewBuilder
    private func cell(label: String, isSelected: Bool) -> some View {
        let state: String? = {
            switch label {
            case "BEEP":  return vm.beepOn.map { $0 ? "ON" : "OFF" }
            case "START": return vm.startInOperate.map { $0 ? "OPER" : "STBY" }
            default:      return nil
            }
        }()

        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .monospaced))
            if let state {
                Text(state)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? .black : LCDStyle.green.opacity(0.7))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(isSelected ? .black : LCDStyle.green)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? LCDStyle.green : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? LCDStyle.green.opacity(0.8) : Color.clear, lineWidth: 1)
        )
    }
}
