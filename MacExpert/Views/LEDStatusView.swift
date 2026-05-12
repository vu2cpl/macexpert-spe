import SwiftUI

struct LEDStatusView: View {
    @Environment(AmplifierViewModel.self) private var vm

    var body: some View {
        // SERIAL and POWER track the WS / serial link itself, so they
        // stay lit even when the amp's CPU is off — that's the FTDI
        // link the gateway distinguishes from amp liveness.
        //
        // OPER / TX / ALARM derive from stale CSV state when the amp
        // stops responding, so force them gray once `isAmpResponding`
        // flips false. SET and TUNE are local-state driven and stay
        // accurate regardless.
        HStack(spacing: 0) {
            LEDIndicator(label: "SERIAL", color: vm.isConnected ? .green : .gray)
            LEDIndicator(label: "POWER", color: vm.isConnected ? .green : .gray)
            LEDIndicator(label: "OPER", color: operateColor)
            LEDIndicator(label: "TUNE", color: tuneColor)
            LEDIndicator(label: "TX", color: txColor)
            LEDIndicator(label: "ALARM", color: alarmColor)
            LEDIndicator(label: "SET", color: vm.isInSetupMode ? .green : .gray)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.10)))
    }

    private var operateColor: Color {
        guard vm.isAmpResponding else { return .gray }
        return vm.state.opStatus == "Oper" ? .orange : .gray
    }

    private var txColor: Color {
        guard vm.isAmpResponding else { return .gray }
        return vm.state.txStatus == "TX" ? .red : .gray
    }

    private var tuneColor: Color {
        // Lit only while an ATU tune is actively running. Driven off the
        // app's own TUNE-press tracker with a timeout — amp-panel tune
        // presses won't light this until we identify a reliable signal
        // for them in the RCU or CSV streams.
        vm.isTuningInProgress ? .yellow : .gray
    }

    private var alarmColor: Color {
        guard vm.isAmpResponding else { return .gray }
        if !vm.state.error.isEmpty { return .red }
        if !vm.state.warnings.isEmpty { return .orange }
        return .gray
    }
}

private struct LEDIndicator: View {
    let label: String
    let color: Color

    private var isActive: Bool { color != .gray }

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(isActive ? color : Color(white: 0.25))
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? color.opacity(0.7) : .clear, radius: 4)
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
    }
}
