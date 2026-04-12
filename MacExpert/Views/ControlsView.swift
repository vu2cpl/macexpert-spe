import SwiftUI

struct ControlsView: View {
    @Environment(AmplifierViewModel.self) private var vm
    @State private var showPowerOffConfirm = false
    @State private var showPowerOnConfirm = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(spacing: 6) {
            // 3x4 button grid
            LazyVGrid(columns: columns, spacing: 4) {
                PanelButton("OPER", icon: "power", accent: vm.state.opStatus == "Oper" ? .orange : nil) {
                    vm.sendCommand(.operate)
                }
                PanelButton("ANT", icon: "antenna.radiowaves.left.and.right") {
                    vm.sendCommand(.antenna)
                }
                PanelButton("TUNE", icon: "tuningfork") {
                    vm.sendCommand(.tune)
                }
                PanelButton("INPUT", icon: "cable.connector.horizontal") {
                    vm.sendCommand(.input)
                }

                PanelButton("POWER", icon: "bolt.fill") {
                    vm.sendCommand(.power)
                }
                PanelButton("BND -", icon: "minus") {
                    vm.sendCommand(.bandDown)
                }
                PanelButton("BND +", icon: "plus") {
                    vm.sendCommand(.bandUp)
                }
                PanelButton("DISP", icon: "display") {
                    vm.sendCommand(.display)
                }

                PanelButton("\u{25C0}", icon: "chevron.left") {
                    vm.sendCommand(.leftArrow)
                }
                PanelButton("\u{25B6}", icon: "chevron.right") {
                    vm.sendCommand(.rightArrow)
                }
                PanelButton("CAT", icon: "point.3.connected.trianglepath.dotted") {
                    vm.sendCommand(.cat)
                }
                PanelButton("SET", icon: "gearshape") {
                    vm.sendCommand(.set)
                }
            }

            // Power on/off
            HStack(spacing: 6) {
                if vm.connectionMode == .websocket {
                    Button {
                        showPowerOnConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power").font(.system(size: 10))
                            Text("POWER ON").font(.system(size: 10, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green.opacity(0.8))
                    .confirmationDialog("Power On the amplifier?", isPresented: $showPowerOnConfirm) {
                        Button("Power On") { vm.powerOn() }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                Button {
                    showPowerOffConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power").font(.system(size: 10))
                        Text("POWER OFF").font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
                .confirmationDialog("Power Off the amplifier?", isPresented: $showPowerOffConfirm) {
                    Button("Power Off", role: .destructive) { vm.powerOff() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.13)))
    }
}

struct PanelButton: View {
    let title: String
    let icon: String
    var accent: Color?
    let action: () -> Void

    init(_ title: String, icon: String, accent: Color? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.accent = accent; self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent ?? .cyan)
                Text(title)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(accent ?? Color(white: 0.55))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke((accent ?? .cyan).opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
