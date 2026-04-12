import SwiftUI

struct AlertBarView: View {
    @Environment(AmplifierViewModel.self) private var vm

    var body: some View {
        if !alertText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                Text(alertText)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(10)
            .foregroundStyle(isError ? .red : .orange)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((isError ? Color.red : Color.orange).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke((isError ? Color.red : Color.orange).opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
    }

    private var alertText: String {
        if !vm.state.error.isEmpty { return vm.state.error }
        if !vm.state.warnings.isEmpty { return vm.state.warnings }
        return ""
    }

    private var isError: Bool { !vm.state.error.isEmpty }
}
