import SwiftUI

struct ContentView: View {
    @Environment(AmplifierViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("SPE \(vm.detectedModel.displayName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                ConnectionIndicator(isConnected: vm.isConnected, status: vm.statusMessage)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))

            ScrollView {
                VStack(spacing: 6) {
                    ConnectionView()

                    if vm.isConnected {
                        AlertBarView()
                        PowerDisplayView()
                        GaugesView()
                        StatusChipsView()
                        ControlsView()
                    }
                }
                .padding(8)
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .background(Color(white: 0.11))
        .preferredColorScheme(.dark)
    }
}

struct ConnectionIndicator: View {
    let isConnected: Bool
    let status: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? Color.green : Color.red.opacity(0.7))
                .frame(width: 7, height: 7)
                .shadow(color: isConnected ? .green.opacity(0.6) : .clear, radius: 3)
            Text(status.isEmpty ? (isConnected ? "Connected" : "Disconnected") : status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
