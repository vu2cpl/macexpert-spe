import SwiftUI
import AppKit

/// Collapsible card that drives the labeled RCU display-packet capture pipeline.
/// Mirrors the layout/styling of `ConnectionView` so it slots in naturally.
struct CaptureView: View {
    @Environment(AmplifierViewModel.self) private var vm
    @State private var isExpanded = false

    var body: some View {
        @Bindable var vm = vm
        let logger = vm.captureLogger

        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(logger.isRunning ? .red : .orange)
                    Text("RCU Capture")
                        .font(.system(size: 13, weight: .semibold))
                    if logger.isRunning {
                        Text("· REC")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if logger.isRunning {
                        Text("\(logger.packetCount) pkt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    HStack {
                        Text("Label").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                        TextField("e.g. OP_14MHz_Ant1", text: $vm.captureLogger.currentLabel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    HStack {
                        if !vm.captureErrorMessage.isEmpty {
                            Text(vm.captureErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        } else if let url = logger.fileURL {
                            Text(url.lastPathComponent)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No active capture")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if logger.fileURL != nil {
                            Button {
                                if let url = logger.fileURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help("Reveal in Finder")
                            .controlSize(.small)
                        }
                        if logger.isRunning {
                            Button("Grab Frame") { vm.grabOneFrame() }
                                .controlSize(.regular)
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .keyboardShortcut(.space, modifiers: [])
                        }
                        Button(logger.isRunning ? "Stop" : "Start Capture") {
                            if logger.isRunning {
                                vm.stopCapture()
                            } else {
                                vm.startCapture(label: logger.currentLabel)
                            }
                        }
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                        .tint(logger.isRunning ? .red.opacity(0.8) : .orange)
                        .disabled(!canCapture)
                    }

                    Text(helpText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)))
    }

    private var canCapture: Bool {
        vm.isConnected && vm.connectionMode == .serial
    }

    private var helpText: String {
        if !vm.isConnected {
            return "Connect to the amp first."
        }
        if vm.connectionMode != .serial {
            return "Capture is serial-only — RCU packets aren't proxied through spe-remote."
        }
        if vm.captureLogger.isRunning {
            return "Set the amp to a screen, edit the label, then click Grab Frame (or press Space). Repeat for each screen you want captured."
        }
        return "Opens a fresh capture file. Use Grab Frame to take one LCD snapshot at a time with the current label."
    }
}
