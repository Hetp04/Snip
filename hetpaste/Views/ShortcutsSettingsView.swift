import AppKit
import SwiftUI
import Carbon

// MARK: - KeyRecorderView (NSViewRepresentable)

/// A compact key-recorder button. When focused it captures the next keypress
/// and reports it as a KeyCombination via the binding.
struct KeyRecorderView: NSViewRepresentable {
    @Binding var combination: KeyCombination
    var isRecording: Bool
    var onStartRecording: () -> Void
    var onStopRecording: () -> Void
    var onCancelRecording: (() -> Void)? = nil

    func makeNSView(context: Context) -> KeyRecorderButton {
        let btn = KeyRecorderButton()
        btn.coordinator = context.coordinator
        return btn
    }

    func updateNSView(_ nsView: KeyRecorderButton, context: Context) {
        nsView.combination = combination
        nsView.isRecording = isRecording
        nsView.updateAppearance()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: KeyRecorderView
        init(_ parent: KeyRecorderView) { self.parent = parent }

        func didRecord(_ combo: KeyCombination) {
            parent.combination = combo
            parent.onStopRecording()
        }
        func startRecording() { parent.onStartRecording() }
        func cancelRecording() {
            if let onCancelRecording = parent.onCancelRecording {
                onCancelRecording()
            } else {
                parent.onStopRecording()
            }
        }
    }
}

// MARK: - KeyRecorderButton

@MainActor
final class KeyRecorderButton: NSButton {
    weak var coordinator: KeyRecorderView.Coordinator?
    var combination: KeyCombination = KeyCombination(key: "C", modifiers: [.command])
    var isRecording: Bool = false {
        didSet { updateAppearance() }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        bezelStyle = .roundedDisclosure
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        focusRingType = .none
        updateAppearance()
        target = self
        action = #selector(handleClick)
    }

    @objc private func handleClick() {
        if isRecording {
            coordinator?.cancelRecording()
        } else {
            window?.makeFirstResponder(self)
            coordinator?.startRecording()
        }
    }

    func updateAppearance() {
        let label: String
        if isRecording {
            label = "Press keys…"
            layer?.backgroundColor = NSColor(hex: "#FFF3F2").cgColor
            layer?.borderColor = NSColor(hex: "#D94A3D").cgColor
            layer?.borderWidth = 1
            attributedTitle = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(hex: "#D94A3D")
            ])
        } else {
            label = keyCombinationLabel(combination)
            layer?.backgroundColor = NSColor(hex: "#F5F5F3").cgColor
            layer?.borderColor = NSColor(hex: "#E7E7E3").cgColor
            layer?.borderWidth = 1
            attributedTitle = NSAttributedString(string: label, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(hex: "#20201F")
            ])
        }
    }

    private func keyCombinationLabel(_ combo: KeyCombination) -> String {
        var parts: [String] = []
        if combo.modifiers.contains(.control) { parts.append("⌃") }
        if combo.modifiers.contains(.option)  { parts.append("⌥") }
        if combo.modifiers.contains(.shift)   { parts.append("⇧") }
        if combo.modifiers.contains(.command) { parts.append("⌘") }
        parts.append(combo.key == "Space" ? "Space" : combo.key.uppercased())
        return parts.joined()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            coordinator?.cancelRecording()
            return
        }

        // Ignore pure modifier-only events
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !event.keyCode.isModifierKeyCode else { return }

        var flags = KeyCombination.ModifierFlags()
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option)  { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift)   { flags.insert(.shift) }

        let keyString = keyStringFromEvent(event)
        let combo = KeyCombination(key: keyString, modifiers: flags)
        coordinator?.didRecord(combo)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
    }

    private func keyStringFromEvent(_ event: NSEvent) -> String {
        // Named keys
        switch Int(event.keyCode) {
        case kVK_Space:   return "Space"
        case kVK_Return:  return "Return"
        case kVK_Escape:  return "Esc"
        case kVK_Delete:  return "Delete"
        case kVK_Tab:     return "Tab"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        default: break
        }
        // Use characters if available
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            return chars
        }
        return "?"
    }
}

private extension UInt16 {
    var isModifierKeyCode: Bool {
        [kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
         kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl,
         kVK_CapsLock, kVK_Function].map(UInt16.init).contains(self)
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: hexStr).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - ShortcutRow

struct ShortcutRow: View {
    let title: String
    let description: String
    @Binding var combination: KeyCombination
    @Binding var recordingID: String?
    let id: String
    var onCommit: (KeyCombination) -> Void

    private var isRecording: Bool { recordingID == id }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#20201F"))
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "#777775"))
            }
            Spacer()
            KeyRecorderView(
                combination: $combination,
                isRecording: isRecording,
                onStartRecording: { recordingID = id },
                onStopRecording: {
                    recordingID = nil
                    onCommit(combination)
                }
            )
            .frame(width: 120, height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - ShortcutsSettingsCard

struct ShortcutsSettingsCard: View {
    @ObservedObject var manager: PsychoCopyManager
    @State private var recordingID: String? = nil

    // Local bindings that mirror the manager settings
    @State private var toggleCombo: KeyCombination = KeyCombination(key: "C", modifiers: [.command, .option])
    @State private var clearCombo: KeyCombination = KeyCombination(key: "X", modifiers: [.command, .option, .shift])
    @State private var reversePasteCombo: KeyCombination = KeyCombination(key: "V", modifiers: [.command, .option])
    @State private var searchCombo: KeyCombination = KeyCombination(key: "F", modifiers: [.option])

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#F4F4F2"))
                        .frame(width: 40, height: 40)
                    Image(systemName: "keyboard")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color(hex: "#3D3D3A"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#20201F"))
                    Text("Customize your global keyboard shortcuts.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: "#777775"))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Divider
            shortcutDivider()

            ShortcutRow(
                title: "Toggle Sequential Paste",
                description: "Activate or deactivate multi-copy mode",
                combination: $toggleCombo,
                recordingID: $recordingID,
                id: "toggle"
            ) { manager.updateToggleHotkey($0) }

            shortcutDivider()

            ShortcutRow(
                title: "Clear Copy Queue",
                description: "Empty the sequential paste queue",
                combination: $clearCombo,
                recordingID: $recordingID,
                id: "clear"
            ) { manager.updateClearQueueHotkey($0) }

            shortcutDivider()

            ShortcutRow(
                title: "Reverse Paste",
                description: "Paste the previous item in queue order",
                combination: $reversePasteCombo,
                recordingID: $recordingID,
                id: "reversePaste"
            ) { manager.updateReversePasteHotkey($0) }

            shortcutDivider()

            ShortcutRow(
                title: "Open Search",
                description: "Focus the clipboard history search field",
                combination: $searchCombo,
                recordingID: $recordingID,
                id: "search"
            ) { manager.updateSearchHotkey($0) }
        }
        .onAppear {
            syncFromSettings()
        }
        .onChange(of: manager.settings.toggleHotkey) { syncFromSettings() }
    }

    private func syncFromSettings() {
        toggleCombo = manager.settings.toggleHotkey
        clearCombo = manager.settings.clearQueueHotkey
        reversePasteCombo = manager.settings.reversePasteHotkey
        searchCombo = manager.settings.searchHotkey
    }

    @ViewBuilder
    private func shortcutDivider() -> some View {
        Divider()
            .background(Color(hex: "#E7E7E3"))
            .padding(.leading, 16)
    }
}
