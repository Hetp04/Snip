import AppKit
import SwiftUI

// MARK: - Design Tokens

private enum DS {
    // Background
    static let pageBg         = Color(hex: "#FFFFFF")
    // Cards
    static let card           = Color(hex: "#FFFFFF")
    static let cardBorder     = Color(hex: "#E7E7E3")
    // Typography
    static let labelPrimary   = Color(hex: "#20201F")
    static let labelSecondary = Color(hex: "#777775")
    static let labelTertiary  = Color(hex: "#92928F")
    // Icon containers
    static let iconBg         = Color(hex: "#F4F4F2")
    static let iconFg         = Color(hex: "#3D3D3A")
    // Controls
    static let toggleTrack    = Color(hex: "#DADADA")
    static let selectionBg    = Color(hex: "#F3F3F1")
    static let selectorBorder = Color(hex: "#E4E4E1")
    static let utilBtn        = Color(hex: "#F5F5F3")
    static let divider        = Color(hex: "#E7E7E3")
    // Destructive
    static let destructive    = Color(hex: "#D94A3D")

    // Border radius
    static let rCard: CGFloat    = 18
    static let rIconBox: CGFloat = 12
    static let rSelector: CGFloat = 10
    static let rDropdown: CGFloat = 12
    static let rDropRow: CGFloat  = 8
    static let rUtilBtn: CGFloat  = 8
    static let rDeleteBtn: CGFloat = 9
    static let rHeaderGroup: CGFloat = 10
}

// MARK: - Navigation destination enum

private enum SettingsDestination: Hashable {
    case shortcuts
    case aiProvider
    case storage
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var manager: PsychoCopyManager
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject private var privacy = PrivacySettings.shared
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            mainPage
                .navigationDestination(for: SettingsDestination.self) { dest in
                    switch dest {
                    case .shortcuts:
                        ShortcutsDetailPage(manager: manager, navPath: $navPath)
                    case .aiProvider:
                        AIProviderDetailPage(navPath: $navPath)
                    case .storage:
                        StorageManagementPage(navPath: $navPath, viewModel: viewModel)
                    }
                }
        }
        .background(DS.pageBg)
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack(alignment: .center) {
                Text("Settings")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(DS.labelPrimary)
                Spacer()
                HStack(spacing: 0) {
                    SettingsHeaderButton(
                        symbol: viewModel.isClipboardCapturePaused ? "play.fill" : "pause.fill",
                        help: viewModel.isClipboardCapturePaused ? "Resume Clipboard Capture" : "Pause Clipboard Capture",
                        action: viewModel.toggleClipboardCapturePaused
                    )
                    Rectangle()
                        .fill(DS.cardBorder)
                        .frame(width: 1, height: 16)
                    SettingsHeaderButton(
                        symbol: "power",
                        help: "Quit",
                        action: { NSApplication.shared.terminate(nil) }
                    )
                }
                .background(DS.utilBtn)
                .clipShape(RoundedRectangle(cornerRadius: DS.rHeaderGroup))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rHeaderGroup)
                        .stroke(DS.cardBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)

            // ── Content ─────────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    // Section 0: System settings
                    SettingsCard {
                        SettingsIconRow(
                            symbol: "power.circle",
                            title: "Launch at Login",
                            description: "Start hetpaste silently in the background when you turn on your Mac. Required for seamless iCloud sync when the app is closed."
                        ) {
                            Toggle("", isOn: $settingsViewModel.launchAtLogin)
                                .toggleStyle(MonochromeToggleStyle())
                                .labelsHidden()
                        }
                    }

                    // Section 1: Sequential Paste
                    SettingsCard {
                        SettingsIconRow(
                            symbol: "doc.on.doc",
                            title: "Sequential Paste",
                            description: "Allows you to copy multiple items sequentially and paste them in order."
                        ) {
                            Toggle("", isOn: Binding(
                                get: { manager.isMultiCopyModeActive },
                                set: { newValue in
                                    if newValue { manager.activateMultiCopyMode() }
                                    else { manager.deactivateMultiCopyMode() }
                                }
                            ))
                            .toggleStyle(MonochromeToggleStyle())
                            .labelsHidden()
                        }
                    }

                    // Section 2: Shortcuts (nav row → detail page)
                    SettingsCard {
                        SettingsNavRow(
                            symbol: "keyboard",
                            title: "Keyboard Shortcuts",
                            description: "Choose the keys you use for paste, queue, and search"
                        ) { navPath.append(SettingsDestination.shortcuts) }
                    }

                    // Section 3: Clear Clipboard History
                    SettingsCard {
                        ClipboardHistoryClearControl(viewModel: viewModel)
                    }

                    // Section 4: iCloud Library + Sync Diagnostics (grouped)
                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingsIconRow(
                                symbol: "cloud",
                                title: "iCloud Library",
                                description: viewModel.cloudSyncState.title
                            ) {
                                Button("Sync Now") { viewModel.syncNow() }
                                    .disabled(viewModel.cloudSyncState == .syncing)
                                    .buttonStyle(UtilityButtonStyle())
                            }
                            CardDivider()
                            SettingsIconRow(
                                symbol: "waveform.path.ecg",
                                title: "Sync Diagnostics",
                                description: syncDiagnosticsText
                            )
                            CardDivider()
                            SettingsNavRow(
                                symbol: "internaldrive",
                                title: "Storage Management",
                                description: "Manage local cached copies and review large-transfer status"
                            ) { navPath.append(SettingsDestination.storage) }
                        }
                    }

                    // Section 5: External AI Search + AI Provider
                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingsIconRow(
                                symbol: "magnifyingglass",
                                title: "External AI Search",
                                description: "Allow clipboard-derived text to be sent to your configured AI provider for semantic search."
                            ) {
                                Toggle("", isOn: $privacy.allowsExternalAI)
                                    .toggleStyle(MonochromeToggleStyle())
                                    .labelsHidden()
                            }
                            CardDivider()
                            SettingsNavRow(
                                symbol: "brain.head.profile",
                                title: "AI Provider",
                                description: "Configure your OpenRouter API key and model"
                            ) { navPath.append(SettingsDestination.aiProvider) }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .background(DS.pageBg)
    }

    private var syncDiagnosticsText: String {
        var parts: [String] = []
        parts.append("Queued changes: \(viewModel.cloudDiagnostics.queuedOperationCount)")
        if let last = viewModel.cloudDiagnostics.lastSuccessfulSync {
            parts.append("Last successful sync: \(last.formatted(date: .abbreviated, time: .shortened))")
        }
        if let retry = viewModel.cloudDiagnostics.nextRetryAt {
            parts.append("Next retry: \(retry.formatted(date: .omitted, time: .shortened))")
        }
        if let err = viewModel.cloudDiagnostics.lastError {
            parts.append("Error: \(err)")
        }
        if viewModel.cloudDiagnostics.isLargeTransferActive {
            parts.append("Large transfer: \(ByteCountFormatter.string(fromByteCount: viewModel.cloudDiagnostics.transferCompletedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: viewModel.cloudDiagnostics.transferTotalBytes, countStyle: .file))")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Shared Card Container

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(DS.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.rCard))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rCard)
                .stroke(DS.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Settings Nav Row (disclosure arrow → navigates to detail page)

private struct SettingsNavRow: View {
    let symbol: String
    let title: String
    let description: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.rIconBox)
                        .fill(DS.iconBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(DS.iconFg)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.labelPrimary)
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DS.labelSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.labelTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isHovering ? DS.selectionBg : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Shortcuts Detail Page

struct ShortcutsDetailPage: View {
    @ObservedObject var manager: PsychoCopyManager
    @Binding var navPath: NavigationPath
    @State private var recordingID: String? = nil
    @State private var toggleCombo: KeyCombination = KeyCombination(key: "C", modifiers: [.command, .option])
    @State private var clearCombo: KeyCombination = KeyCombination(key: "X", modifiers: [.command, .option, .shift])
    @State private var reversePasteCombo: KeyCombination = KeyCombination(key: "V", modifiers: [.command, .option])
    @State private var searchCombo: KeyCombination = KeyCombination(key: "F", modifiers: [.option])

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().background(DS.divider)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Info banner
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(DS.labelTertiary)
                        Text("Click a shortcut keycap, press your new key combination, then release. Press Esc to cancel. Changes take effect immediately.")
                            .font(.system(size: 12))
                            .foregroundColor(DS.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(DS.iconBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Shortcuts card
                    SettingsCard {
                        VStack(spacing: 0) {
                            shortcutRow(
                                id: "toggle",
                                symbol: "record.circle",
                                title: "Toggle Sequential Paste",
                                description: "Activate or deactivate multi-copy mode",
                                combo: $toggleCombo
                            ) { manager.updateToggleHotkey($0) }

                            inlineDivider()

                            shortcutRow(
                                id: "clear",
                                symbol: "xmark.circle",
                                title: "Clear Copy Queue",
                                description: "Empty the sequential paste queue",
                                combo: $clearCombo
                            ) { manager.updateClearQueueHotkey($0) }

                            inlineDivider()

                            shortcutRow(
                                id: "reversePaste",
                                symbol: "arrow.uturn.backward.circle",
                                title: "Reverse Paste",
                                description: "Paste the previous item in queue order",
                                combo: $reversePasteCombo
                            ) { manager.updateReversePasteHotkey($0) }

                            inlineDivider()

                            shortcutRow(
                                id: "search",
                                symbol: "magnifyingglass.circle",
                                title: "Open Search",
                                description: "Focus clipboard history search field",
                                combo: $searchCombo
                            ) { manager.updateSearchHotkey($0) }
                        }
                    }

                    // Reset button
                    Button("Reset All to Defaults") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            manager.updateToggleHotkey(KeyCombination(key: "C", modifiers: [.command, .option]))
                            manager.updateClearQueueHotkey(KeyCombination(key: "X", modifiers: [.command, .option, .shift]))
                            manager.updateReversePasteHotkey(KeyCombination(key: "V", modifiers: [.command, .option]))
                            manager.updateSearchHotkey(KeyCombination(key: "F", modifiers: [.option]))
                            syncFromSettings()
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.labelSecondary)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(DS.pageBg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    navPath.removeLast()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text("Settings")
                    }
                    .foregroundColor(DS.labelSecondary)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .principal) {
                Text("Shortcuts")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.labelPrimary)
            }
        }
        .onAppear { syncFromSettings() }
        .onChange(of: manager.settings.toggleHotkey) { syncFromSettings() }
        .onChange(of: manager.settings.clearQueueHotkey) { syncFromSettings() }
        .onChange(of: manager.settings.reversePasteHotkey) { syncFromSettings() }
        .onChange(of: manager.settings.searchHotkey) { syncFromSettings() }
    }

    private func syncFromSettings() {
        toggleCombo = manager.settings.toggleHotkey
        clearCombo = manager.settings.clearQueueHotkey
        reversePasteCombo = manager.settings.reversePasteHotkey
        searchCombo = manager.settings.searchHotkey
    }

    @ViewBuilder
    private func shortcutRow(
        id: String,
        symbol: String,
        title: String,
        description: String,
        combo: Binding<KeyCombination>,
        onCommit: @escaping (KeyCombination) -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.rIconBox)
                    .fill(DS.iconBg)
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DS.iconFg)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.labelPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(DS.labelSecondary)
            }
            Spacer()
            KeyRecorderView(
                combination: combo,
                isRecording: recordingID == id,
                onStartRecording: { recordingID = id },
                onStopRecording: {
                    recordingID = nil
                    onCommit(combo.wrappedValue)
                },
                onCancelRecording: { recordingID = nil }
            )
            .frame(width: 124, height: 28)
            .help(recordingID == id ? "Press Esc to cancel" : "Click to change this shortcut")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func inlineDivider() -> some View {
        Divider()
            .background(DS.divider)
            .padding(.leading, 66)
    }
}

// MARK: - AI Provider Detail Page

struct AIProviderDetailPage: View {
    @Binding var navPath: NavigationPath
    @AppStorage("ai.provider.apiKey") private var legacyAPIKey: String = ""
    @AppStorage("ai.provider.model") private var selectedModel: String = "openai/text-embedding-3-large"
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var savedFlash = false

    private let availableModels = [
        "openai/text-embedding-3-large",
        "openai/text-embedding-3-small",
        "openai/text-embedding-ada-002"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().background(DS.divider)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Info banner
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(DS.labelTertiary)
                            .padding(.top, 1)
                        Text("hetpaste uses OpenRouter to power semantic search. Get a free API key at openrouter.ai — no credit card needed for free-tier models.")
                            .font(.system(size: 12))
                            .foregroundColor(DS.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(DS.iconBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // API Key card
                    SettingsCard {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OpenRouter API Key")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.labelPrimary)

                                HStack(spacing: 8) {
                                    Group {
                                        if showKey {
                                            TextField("sk-or-...", text: $apiKey)
                                        } else {
                                            SecureField("sk-or-...", text: $apiKey)
                                        }
                                    }
                                    .font(.system(size: 13, design: .monospaced))
                                    .textFieldStyle(.plain)
                                    .frame(maxWidth: .infinity)

                                    Button {
                                        showKey.toggle()
                                    } label: {
                                        Image(systemName: showKey ? "eye.slash" : "eye")
                                            .font(.system(size: 13))
                                            .foregroundColor(DS.labelTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(DS.iconBg)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(DS.selectorBorder, lineWidth: 1)
                                )

                                Text(apiKey.isEmpty ? "Not configured — AI search will be unavailable." : apiKeyStatus)
                                    .font(.system(size: 11))
                                    .foregroundColor(apiKey.isEmpty ? DS.labelTertiary : DS.labelSecondary)
                            }
                            .padding(16)

                            Divider().background(DS.divider).padding(.leading, 16)

                            // Model picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Embedding Model")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.labelPrimary)

                                Picker("", selection: $selectedModel) {
                                    ForEach(availableModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 13, design: .monospaced))

                                Text("text-embedding-3-large offers the best semantic search accuracy. Use -small for faster, cheaper queries.")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.labelTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                        }
                    }

                    // Save note
                    HStack(spacing: 6) {
                        Image(systemName: savedFlash ? "checkmark.circle.fill" : "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(savedFlash ? Color(hex: "#3D9C52") : DS.labelTertiary)
                        Text(savedFlash ? "Saved securely in Keychain. Changes apply on the next search." : "Your key is stored securely in this Mac’s Keychain and never synced to iCloud.")
                            .font(.system(size: 11))
                            .foregroundColor(savedFlash ? Color(hex: "#3D9C52") : DS.labelTertiary)
                    }
                    .animation(.easeInOut(duration: 0.2), value: savedFlash)
                    .onChange(of: apiKey) {
                        try? SecureCredentialStore.setOpenRouterAPIKey(apiKey)
                        savedFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(DS.pageBg)
        .onAppear {
            // One-time migration from the old plaintext preference, then erase
            // it so it cannot remain in the app's preferences database.
            if SecureCredentialStore.openRouterAPIKey.isEmpty, !legacyAPIKey.isEmpty {
                try? SecureCredentialStore.setOpenRouterAPIKey(legacyAPIKey)
            }
            legacyAPIKey = ""
            apiKey = SecureCredentialStore.openRouterAPIKey
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    navPath.removeLast()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text("Settings")
                    }
                    .foregroundColor(DS.labelSecondary)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .principal) {
                Text("AI Provider")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.labelPrimary)
            }
        }
    }

    private var apiKeyStatus: String {
        if apiKey.hasPrefix("sk-or-") {
            return "✓ Valid OpenRouter key format"
        }
        return "Unrecognized key format — verify at openrouter.ai"
    }
}

// MARK: - Storage Management

private struct StorageManagementPage: View {
    @Binding var navPath: NavigationPath
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @State private var localBytes: Int64 = AssetCache.shared.storageUsageBytes()
    @State private var protectedBytes: Int64 = AssetCache.shared.protectedStorageUsageBytes()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().background(DS.divider)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        SettingsIconRow(
                            symbol: "internaldrive",
                            title: "Local cached content",
                            description: ByteCountFormatter.string(fromByteCount: localBytes, countStyle: .file)
                        ) {
                            Button("Clear Cache") {
                                AssetCache.shared.clearUnprotected()
                                refreshUsage()
                            }
                            .buttonStyle(UtilityButtonStyle())
                        }
                        CardDivider()
                        SettingsIconRow(
                            symbol: "arrow.triangle.2.circlepath.icloud",
                            title: "iCloud Library",
                            description: "\(viewModel.cloudDiagnostics.queuedOperationCount) queued changes. Apple does not expose a precise per-app private CloudKit storage balance to macOS apps."
                        )
                    }

                    if viewModel.cloudDiagnostics.isLargeTransferActive {
                        SettingsCard {
                            SettingsIconRow(
                                symbol: "arrow.up.arrow.down.circle",
                                title: "Large transfer in progress",
                                description: "\(ByteCountFormatter.string(fromByteCount: viewModel.cloudDiagnostics.transferCompletedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: viewModel.cloudDiagnostics.transferTotalBytes, countStyle: .file)) transferred. It resumes after interruptions while its local source remains available."
                            )
                        }
                    }

                    Text(protectedBytes > 0
                         ? "\(ByteCountFormatter.string(fromByteCount: protectedBytes, countStyle: .file)) is protected because it is needed by an unfinished upload. Clear Cache removes everything else, but never deletes protected transfer data or iCloud cards."
                         : "Clearing the cache never deletes clipboard cards from iCloud. Files required by an unfinished upload are protected and will not be removed.")
                        .font(.system(size: 12))
                        .foregroundColor(DS.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
        }
        .background(DS.pageBg)
        .onAppear { refreshUsage() }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { navPath.removeLast() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium))
                        Text("Settings")
                    }
                    .foregroundColor(DS.labelSecondary)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .principal) {
                Text("Storage Management")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.labelPrimary)
            }
        }
    }

    private func refreshUsage() {
        localBytes = AssetCache.shared.storageUsageBytes()
        protectedBytes = AssetCache.shared.protectedStorageUsageBytes()
    }
}

// MARK: - Settings Icon Row

private struct SettingsIconRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let description: String
    var trailing: (() -> Trailing)? = nil

    init(symbol: String, title: String, description: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon box
            ZStack {
                RoundedRectangle(cornerRadius: DS.rIconBox)
                    .fill(DS.iconBg)
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(DS.iconFg)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.labelPrimary)
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }

            Spacer(minLength: 12)

            if let trailing = trailing {
                trailing()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// Convenience init without trailing
extension SettingsIconRow where Trailing == EmptyView {
    init(symbol: String, title: String, description: String) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.trailing = nil
    }
}

// MARK: - Card Divider

private struct CardDivider: View {
    var body: some View {
        Divider()
            .frame(height: 1)
            .background(DS.divider)
            .padding(.leading, 72)
    }
}

// MARK: - Header Buttons

private struct SettingsHeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.iconFg)
                .frame(width: 32, height: 26)
                .background(isHovering ? DS.cardBorder.opacity(0.6) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Utility Button Style

private struct UtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(DS.labelPrimary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(configuration.isPressed ? DS.cardBorder : DS.utilBtn)
            .clipShape(RoundedRectangle(cornerRadius: DS.rUtilBtn))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rUtilBtn)
                    .stroke(DS.cardBorder, lineWidth: 1)
            )
    }
}

// MARK: - Monochrome Toggle Style

private struct MonochromeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? DS.labelPrimary : DS.toggleTrack)
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .padding(2)
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
            }
            .onTapGesture { configuration.isOn.toggle() }
            .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
        }
    }
}

// MARK: - Clear Clipboard History Control

private struct ClipboardHistoryClearControl: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @AppStorage("clipboard-history-selected-range") private var storedSelection = "last7Days"
    @AppStorage("clipboard-history-custom-start") private var storedCustomStart = Date().addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970
    @AppStorage("clipboard-history-custom-end") private var storedCustomEnd = Date().timeIntervalSince1970

    @State private var isRangeMenuExpanded = false
    @State private var isCustomRangePresented = false
    @State private var tempCustomStart = Date()
    @State private var tempCustomEnd = Date()
    @State private var activeAlert: HistoryAlert?

    private enum HistoryAlert: Identifiable {
        case confirmation(range: ClipboardHistoryRange, count: Int)
        case error(String)
        var id: String {
            switch self {
            case let .confirmation(range, count): return "confirm-\(range.id)-\(count)"
            case let .error(message): return "error-\(message)"
            }
        }
    }

    private let presets: [ClipboardHistoryRange] = [.lastHour, .today, .last24Hours, .last7Days, .last30Days, .allHistory]

    var body: some View {
        let count = matchingCount
        VStack(alignment: .leading, spacing: 0) {
            // ── Section header row (icon + title + description) ─────
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.rIconBox)
                        .fill(DS.iconBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(DS.iconFg)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear Clipboard History")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.labelPrimary)
                    Text("Permanently remove saved clipboard items.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DS.labelSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // ── Time Range area ─────────────────────────────────────
            VStack(spacing: 0) {
                // Selector row
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isRangeMenuExpanded.toggle()
                        if !isRangeMenuExpanded { isCustomRangePresented = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Time Range")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.labelPrimary)
                        Spacer()
                        Text(selectedDisplayTitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DS.labelPrimary)
                        Image(systemName: isRangeMenuExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.labelSecondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(DS.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rSelector))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rSelector)
                            .stroke(DS.selectorBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isDeletingClipboardHistory)

                // Dropdown
                if isRangeMenuExpanded {
                    VStack(spacing: 0) {
                        ForEach(presets) { range in
                            DropdownOptionRow(
                                range: range,
                                isSelected: storedSelection == storageKey(for: range)
                            ) {
                                storedSelection = storageKey(for: range)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isRangeMenuExpanded = false
                                }
                            }
                        }

                        // Divider before Custom Range
                        Rectangle()
                            .fill(DS.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)

                        DropdownOptionRow(
                            range: .custom(start: .now, end: .now),
                            isSelected: storedSelection == "custom",
                            customTitle: "Custom Range…"
                        ) {
                            tempCustomStart = Date(timeIntervalSince1970: storedCustomStart)
                            tempCustomEnd = Date(timeIntervalSince1970: storedCustomEnd)
                            isCustomRangePresented = true
                        }
                        .popover(isPresented: $isCustomRangePresented, arrowEdge: .top) {
                            customRangePopover
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 5)
                    .background(DS.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rDropdown))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rDropdown)
                            .stroke(DS.selectorBorder, lineWidth: 1)
                    )
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .padding(.horizontal, 20)

            // ── Divider ─────────────────────────────────────────────
            Rectangle()
                .fill(DS.divider)
                .frame(height: 1)
                .padding(.top, 16)

            // ── Bottom action row ────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.labelSecondary)
                Text(count == 0
                     ? "No items in this time range"
                     : "\(count) item\(count == 1 ? "" : "s") will be deleted")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.labelSecondary)
                Spacer()
                deleteButton(count: count)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if viewModel.isDeletingClipboardHistory {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Deleting… \(viewModel.clipboardHistoryDeletionProgress) removed")
                        .font(.system(size: 12))
                        .foregroundColor(DS.labelSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case let .confirmation(range, count):
                let isAll = range.isAllHistory
                let title = isAll ? "Delete All Clipboard History?" : "Delete \(count) Clipboard Item\(count == 1 ? "" : "s")?"
                let message = isAll
                    ? "All saved clipboard items will be permanently deleted from your clipboard history and iCloud.\n\nThis cannot be undone."
                    : "These items will be permanently deleted from your clipboard history and iCloud.\n\nThis cannot be undone."
                let deleteTitle = isAll ? "Delete All History" : "Delete \(count) Item\(count == 1 ? "" : "s")"
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    primaryButton: .destructive(Text(deleteTitle)) {
                        Task { await performDeletion(range) }
                    },
                    secondaryButton: .cancel()
                )
            case let .error(message):
                return Alert(
                    title: Text("Clipboard History Wasn't Fully Deleted"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: Helpers

    private var selectedRange: ClipboardHistoryRange {
        switch storedSelection {
        case "lastHour":   return .lastHour
        case "today":      return .today
        case "last24Hours": return .last24Hours
        case "last30Days": return .last30Days
        case "allHistory": return .allHistory
        case "custom":
            return .custom(
                start: Date(timeIntervalSince1970: storedCustomStart),
                end: Date(timeIntervalSince1970: storedCustomEnd)
            )
        default: return .last7Days
        }
    }

    private var selectedDisplayTitle: String {
        if case .custom = selectedRange {
            let bounds = selectedRange.bounds()
            if let start = bounds.start, let end = bounds.end {
                let calendar = Calendar.current
                let startYear = calendar.component(.year, from: start)
                let endYear = calendar.component(.year, from: end)
                let currentYear = calendar.component(.year, from: Date())
                let fmt = DateFormatter()
                if startYear == endYear && startYear == currentYear {
                    fmt.dateFormat = "MMM d"
                    return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
                } else if startYear == endYear {
                    fmt.dateFormat = "MMM d"
                    return "\(fmt.string(from: start)) – \(fmt.string(from: end)), \(startYear)"
                } else {
                    fmt.dateFormat = "MMM d, yyyy"
                    return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
                }
            }
            return "Custom Range"
        }
        return selectedRange.title
    }

    private var matchingCount: Int { viewModel.clipboardHistoryCount(in: selectedRange) }

    private func deleteButton(count: Int) -> some View {
        let title = count == 0 ? "Delete Items" : "Delete \(count) Item\(count == 1 ? "" : "s")"

        return Button(action: {
            prepareConfirmation(
                for: selectedRange
            )
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(count == 0 ? DS.labelSecondary : .white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(count == 0 ? DS.utilBtn : DS.destructive)
            .clipShape(RoundedRectangle(cornerRadius: DS.rDeleteBtn))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rDeleteBtn)
                    .stroke(count == 0 ? DS.cardBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0 || viewModel.isDeletingClipboardHistory)
    }

    private var customRangePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Range")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.labelPrimary)
            VStack(spacing: 10) {
                DatePicker("From", selection: $tempCustomStart, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                DatePicker("To", selection: $tempCustomEnd, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
            .padding(.vertical, 4)
            Divider().background(DS.divider)
            HStack {
                Button("Cancel") { isCustomRangePresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.labelSecondary)
                Spacer()
                Button("Apply") {
                    storedCustomStart = tempCustomStart.timeIntervalSince1970
                    storedCustomEnd   = tempCustomEnd.timeIntervalSince1970
                    storedSelection   = "custom"
                    isCustomRangePresented = false
                    withAnimation(.easeInOut(duration: 0.15)) { isRangeMenuExpanded = false }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(DS.labelPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 300)
        .background(DS.card)
    }

    private func storageKey(for range: ClipboardHistoryRange) -> String {
        switch range {
        case .lastHour:    return "lastHour"
        case .today:       return "today"
        case .last24Hours: return "last24Hours"
        case .last7Days:   return "last7Days"
        case .last30Days:  return "last30Days"
        case .allHistory:  return "allHistory"
        case .custom:      return "custom"
        }
    }

    private func prepareConfirmation(for range: ClipboardHistoryRange) {
        let resolvedRange: ClipboardHistoryRange
        if range.isAllHistory {
            resolvedRange = .allHistory
        } else {
            let bounds = range.bounds()
            resolvedRange = .custom(start: bounds.start ?? .distantPast, end: bounds.end ?? Date())
        }
        let count = viewModel.clipboardHistoryCount(in: resolvedRange)
        activeAlert = .confirmation(range: resolvedRange, count: count)
    }

    private func performDeletion(_ range: ClipboardHistoryRange) async {
        guard viewModel.clipboardHistoryCount(in: range) > 0 else { return }
        do {
            _ = try await viewModel.deleteClipboardHistory(in: range)
        } catch {
            activeAlert = .error(viewModel.clipboardHistoryDeletionMessage(for: error))
        }
    }
}

// MARK: - Dropdown Option Row

private struct DropdownOptionRow: View {
    let range: ClipboardHistoryRange
    let isSelected: Bool
    var customTitle: String? = nil
    let action: () -> Void
    @State private var isHovering = false

    private var symbol: String {
        switch range {
        case .lastHour:    return "clock"
        case .today:       return "sun.max"
        case .last24Hours: return "clock.arrow.circlepath"
        case .last7Days:   return "calendar"
        case .last30Days:  return "calendar"
        case .allHistory:  return "trash"
        case .custom:      return "calendar.badge.clock"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DS.labelTertiary)
                    .frame(width: 18, alignment: .center)
                Text(customTitle ?? range.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.labelPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.labelPrimary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isSelected
                    ? DS.selectionBg
                    : (isHovering ? DS.selectionBg.opacity(0.6) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.rDropRow))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .onHover { isHovering = $0 }
    }
}
