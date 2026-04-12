import SwiftUI

struct StatusChipsView: View {
    @Environment(AmplifierViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 4) {
            StatusChip(
                label: "STATUS",
                value: vm.state.txStatus,
                accent: vm.state.txStatus == "TX" ? .red : .green
            )
            StatusChip(label: "BAND", value: vm.state.band, accent: .cyan)
            StatusChip(label: "ANT", value: vm.state.txAntenna, accent: .cyan)
            StatusChip(label: "IN", value: vm.state.input, accent: .cyan)
            StatusChip(label: "LEVEL", value: vm.state.pLevel, accent: .cyan)
            StatusChip(
                label: "MODE",
                value: vm.state.opStatus == "Oper" ? "OPER" : "STBY",
                accent: vm.state.opStatus == "Oper" ? .orange : .gray
            )
        }
    }
}

struct StatusChip: View {
    let label: String
    let value: String
    var accent: Color = .cyan

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .tracking(0.5)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(accent.opacity(0.2), lineWidth: 0.5)
        )
    }
}
