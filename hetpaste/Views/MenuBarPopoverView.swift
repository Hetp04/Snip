import SwiftUI
struct MenuBarPopoverView: View {
    @ObservedObject var manager: PsychoCopyManager
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("hetpaste")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Settings")
                Button(action: viewModel.toggleClipboardCapturePaused) {
                    Image(systemName: viewModel.isClipboardCapturePaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help(viewModel.isClipboardCapturePaused ? "Resume Clipboard Capture" : "Pause Clipboard Capture")
                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Quit")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sequential Paste Mode")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Multi-select queueing")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Sequential Paste Mode", isOn: Binding(
                        get: { manager.isMultiCopyModeActive },
                        set: { newValue in
                            if newValue {
                                manager.activateMultiCopyMode()
                            } else {
                                manager.deactivateMultiCopyMode()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if manager.isMultiCopyModeActive {
                    HStack {
                        let count = manager.copyQueue.count
                        Text("\(count) item\(count == 1 ? "" : "s") in queue")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(count > 0 ? Theme.accent : .secondary)
                        Spacer()
                        if count > 0 {
                            Button("Clear") {
                                manager.clearQueue()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .frame(width: 250)
    }
}
