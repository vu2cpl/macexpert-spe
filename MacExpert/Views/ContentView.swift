import SwiftUI

/// PreferenceKey used to measure the natural combined height of the
/// power display + gauges block, so the LCDContainer (used by every
/// sub-menu) can match it exactly. Keeping both the same height means
/// the controls row below doesn't shift when you switch between normal
/// view and SETUP, so mouse-click positions stay put.
struct NormalContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @Environment(AmplifierViewModel.self) private var vm
    /// Measured height of PowerDisplay + Gauges. Populated the first
    /// time the normal view is rendered; stays set afterwards so
    /// sub-menus can match it.
    @State private var normalBlockHeight: CGFloat = 0

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
                    CaptureView()

                    if vm.isConnected {
                        AlertBarView()

                        // RCU parser debug overlay — always visible when
                        // connected so we can see pipeline state (connection
                        // type, callback count, rcuOwner) even if no frames
                        // have arrived.
                        RCUDebugView()

                        // Swap between normal display, setup menu, sub-menus,
                        // and CAT/DISP info overlay.
                        if vm.isShowingInfoScreen {
                            InfoScreenView()
                                .frame(height: normalBlockHeight > 0 ? normalBlockHeight : nil)
                                .transition(.opacity)
                        } else if let subMenu = vm.activeSubMenu {
                            subMenuView(for: subMenu)
                                .frame(height: normalBlockHeight > 0 ? normalBlockHeight : nil)
                                .transition(.opacity)
                        } else if vm.isInSetupMode {
                            SetupMenuView()
                                .frame(height: normalBlockHeight > 0 ? normalBlockHeight : nil)
                                .transition(.opacity)
                        } else if vm.state.opStatus == "Stby"
                                  && !vm.standbyBannerLines.isEmpty {
                            // In STANDBY mirror the amp's LCD as a banner
                            // sized to the menu display height — same
                            // footprint as a SETUP sub-menu so toggling
                            // between STANDBY / SETUP / OPERATE doesn't
                            // shift anything below. Gauges hide here
                            // (they're all zero when idle anyway).
                            StandbyBannerView()
                                .frame(height: normalBlockHeight > 0 ? normalBlockHeight : nil)
                                .transition(.opacity)
                        } else {
                            VStack(spacing: 6) {
                                PowerDisplayView()
                                GaugesView()
                            }
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: NormalContentHeightKey.self,
                                        value: geo.size.height)
                                }
                            )
                            .onPreferenceChange(NormalContentHeightKey.self) { h in
                                if h > 0 { normalBlockHeight = h }
                            }
                            .transition(.opacity)
                        }

                        LEDStatusView()
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

extension ContentView {
    @ViewBuilder
    func subMenuView(for subMenu: AmplifierViewModel.SetupSubMenu) -> some View {
        switch subMenu {
        case .config: ConfigSubMenuView()
        case .antenna: AntennaSubMenuView()
        case .cat: CATSubMenuView()
        case .manualTune: ManualTuneSubMenuView()
        case .display: DisplaySubMenuView()
        case .beep: BeepSubMenuView()
        case .start: StartSubMenuView()
        case .tempFans: TempFansSubMenuView()
        case .alarmsLog: AlarmsLogSubMenuView()
        case .tunAnt: TunAntSubMenuView()
        case .rxAnt: RxAntSubMenuView()
        case .yaesuModel: YaesuModelSubMenuView()
        case .tenTecModel: TenTecModelSubMenuView()
        case .baudRate: BaudRateSubMenuView()
        case .tunAntPort: TunAntPortSubMenuView()
        }
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
