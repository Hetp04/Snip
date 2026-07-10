import SwiftUI
struct SettingsView: View {
    @ObservedObject var manager: PsychoCopyManager
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            Divider()
                .background(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sequential Paste")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Theme.textPrimary)
                            Text("Allows you to copy multiple items sequentially and paste them in order.")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { manager.isMultiCopyModeActive },
                            set: { newValue in
                                if newValue {
                                    manager.activateMultiCopyMode()
                                } else {
                                    manager.deactivateMultiCopyMode()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.9, anchor: .trailing)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                    Divider()
                        .background(Theme.divider)
                }
            }
        }
        .background(Theme.bg)
    }
}