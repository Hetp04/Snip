import Foundation
import Combine
import AppKit
import Carbon
@MainActor
final class PsychoCopyManager: ObservableObject {
    @Published private(set) var isMultiCopyModeActive: Bool = false
    @Published private(set) var copyQueue: CopyQueue = CopyQueue()
    @Published var settings: PsychoCopySettings = PsychoCopySettings()
    @Published var isHUDExpanded: Bool = false
    static let modeChangedNotification = Notification.Name("PsychoCopyModeChanged")
    static let queueChangedNotification = Notification.Name("PsychoCopyQueueChanged")
    static let secureInputBlockedNotification = Notification.Name("PsychoCopySecureInputBlocked")
    static let searchHotkeyChangedNotification = Notification.Name("PsychoCopySearchHotkeyChanged")
    private let hotkeyManager = HotkeyManager.shared
    private(set) var isSimulatingPaste = false
    private var isPastingNow: Bool = false
    var onGlobalPasteRequested: (() -> Void)?
    var onGlobalReversePasteRequested: (() -> Void)?
    private var vKeyCode: CGKeyCode = 0x09 
    private var layoutObserver: NSObjectProtocol?
    init() {
        settings = PsychoCopySettings.load()
        resolveVKeyCode()
        installLayoutObserver()
        setupHotkeys()
    }
    deinit {
        if let obs = layoutObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    private func resolveVKeyCode() {
        vKeyCode = resolvedVKeyCode() ?? 0x09
    }
    private func resolvedVKeyCode() -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let layoutPtr = CFDataGetBytePtr(layoutData)
        guard let layout = layoutPtr?.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1, { $0 }) else {
            return nil
        }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var charCount = 0
        for keyCode in 0..<128 as CountableRange<CGKeyCode> {
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &charCount,
                &chars
            )
            if status == noErr, charCount == 1, chars[0] == 0x0076 { 
                return keyCode
            }
        }
        return nil
    }
    private func installLayoutObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let obs = observer else { return }
                let manager = Unmanaged<PsychoCopyManager>.fromOpaque(obs).takeUnretainedValue()
                DispatchQueue.main.async { manager.resolveVKeyCode() }
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }
    private func setupHotkeys() {
        hotkeyManager.registerToggleHotkey(settings.toggleHotkey) { [weak self] in
            Task { @MainActor in self?.toggleMultiCopyMode() }
        }
        hotkeyManager.registerClearQueueHotkey(settings.clearQueueHotkey) { [weak self] in
            Task { @MainActor in self?.clearQueue() }
        }
    }

    // MARK: - Public hotkey update API

    func updateToggleHotkey(_ combo: KeyCombination) {
        settings.toggleHotkey = combo
        settings.save()
        hotkeyManager.registerToggleHotkey(combo) { [weak self] in
            Task { @MainActor in self?.toggleMultiCopyMode() }
        }
    }

    func updateClearQueueHotkey(_ combo: KeyCombination) {
        settings.clearQueueHotkey = combo
        settings.save()
        hotkeyManager.registerClearQueueHotkey(combo) { [weak self] in
            Task { @MainActor in self?.clearQueue() }
        }
    }

    func updateReversePasteHotkey(_ combo: KeyCombination) {
        settings.reversePasteHotkey = combo
        settings.save()
        // Re-register only when sequential paste mode is active
        if isMultiCopyModeActive {
            hotkeyManager.registerReversePasteHotkey(combo) { [weak self] in
                guard let self, !self.isPastingNow else { return }
                self.onGlobalReversePasteRequested?()
            }
        }
    }

    func updateSearchHotkey(_ combo: KeyCombination) {
        settings.searchHotkey = combo
        settings.save()
        NotificationCenter.default.post(
            name: Self.searchHotkeyChangedNotification,
            object: combo
        )
    }
    private func registerPasteHotkey() {
        let pasteCombo = KeyCombination(key: "V", modifiers: [.command])
        hotkeyManager.registerPasteHotkey(pasteCombo) { [weak self] in
            guard let self, !self.isPastingNow else { return } 
            self.onGlobalPasteRequested?()
        }
        hotkeyManager.registerReversePasteHotkey(settings.reversePasteHotkey) { [weak self] in
            guard let self, !self.isPastingNow else { return }
            self.onGlobalReversePasteRequested?()
        }
    }
    private func unregisterPasteHotkey() {
        hotkeyManager.unregisterPasteHotkey()
        hotkeyManager.unregisterReversePasteHotkey()
    }
    func toggleMultiCopyMode() {
        if isMultiCopyModeActive {
            deactivateMultiCopyMode()
        } else {
            activateMultiCopyMode()
        }
    }
    func activateMultiCopyMode() {
        guard !isMultiCopyModeActive else { return }
        isMultiCopyModeActive = true
        registerPasteHotkey()
        NotificationCenter.default.post(name: Self.modeChangedNotification, object: nil)
    }
    func deactivateMultiCopyMode() {
        guard isMultiCopyModeActive else { return }
        isMultiCopyModeActive = false
        isPastingNow = false
        copyQueue.clear()
        unregisterPasteHotkey()
        NotificationCenter.default.post(name: Self.modeChangedNotification, object: nil)
    }
    func clearQueue() {
        copyQueue.clear()
        NotificationCenter.default.post(name: Self.queueChangedNotification, object: nil)
    }
    func moveItems(from source: IndexSet, to destination: Int) {
        copyQueue.move(from: source, to: destination)
        NotificationCenter.default.post(name: Self.queueChangedNotification, object: nil)
    }
    func removeItems(atOffsets offsets: IndexSet) {
        copyQueue.remove(atOffsets: offsets)
        NotificationCenter.default.post(name: Self.queueChangedNotification, object: nil)
    }
    func handleClipboardChange(_ item: ClipboardItem) {
        guard isMultiCopyModeActive, !isSimulatingPaste else { return }
        copyQueue.enqueue(item)
        NotificationCenter.default.post(name: Self.queueChangedNotification, object: nil)
    }
    func performSequentialPaste(viewModel: ClipboardHistoryViewModel) async -> ClipboardRestoreResult {
        return await _performSequentialPaste(viewModel: viewModel, isReverse: false)
    }
    func performReverseSequentialPaste(viewModel: ClipboardHistoryViewModel) async -> ClipboardRestoreResult {
        return await _performSequentialPaste(viewModel: viewModel, isReverse: true)
    }
    private func _performSequentialPaste(viewModel: ClipboardHistoryViewModel, isReverse: Bool) async -> ClipboardRestoreResult {
        guard isMultiCopyModeActive else {
            return ClipboardRestoreResult(didCopy: false, message: "Multi-copy mode is not active")
        }
        isPastingNow = true
        unregisterPasteHotkey()
        if IsSecureEventInputEnabled() {
            isPastingNow = false
            if isMultiCopyModeActive { registerPasteHotkey() }
            NotificationCenter.default.post(name: Self.secureInputBlockedNotification, object: nil)
            return ClipboardRestoreResult(didCopy: false, message: "Secure field — press ⌘V manually")
        }
        guard !copyQueue.isEmpty else {
            isPastingNow = false
            simulateCmdV()
            try? await Task.sleep(nanoseconds: 30_000_000)
            return ClipboardRestoreResult(didCopy: false, message: "Queue is empty")
        }
        guard let item = isReverse ? copyQueue.dequeueLast() : copyQueue.dequeue() else {
            isPastingNow = false
            if isMultiCopyModeActive { registerPasteHotkey() }
            return ClipboardRestoreResult(didCopy: false, message: "Failed to dequeue item")
        }
        NotificationCenter.default.post(name: Self.queueChangedNotification, object: nil)
        isSimulatingPaste = true
        let result = await viewModel.restoreToPasteboard(item, asPlainText: false)
        isSimulatingPaste = false
        if result.didCopy {
            let expectedCount = NSPasteboard.general.changeCount
            let deadline = Date().addingTimeInterval(0.3)
            while NSPasteboard.general.changeCount != expectedCount && Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000) 
            }
            simulateCmdV()
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        if copyQueue.isEmpty {
            isMultiCopyModeActive = false
            isPastingNow = false
            NotificationCenter.default.post(name: Self.modeChangedNotification, object: nil)
        } else {
            isPastingNow = false
            registerPasteHotkey()
        }
        return result
    }
    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    var toggleHotkeyLabel: String {
        hotkeyLabel(for: settings.toggleHotkey)
    }
    func hotkeyLabel(for combo: KeyCombination) -> String {
        var parts: [String] = []
        if combo.modifiers.contains(.control) { parts.append("⌃") }
        if combo.modifiers.contains(.option)  { parts.append("⌥") }
        if combo.modifiers.contains(.shift)   { parts.append("⇧") }
        if combo.modifiers.contains(.command) { parts.append("⌘") }
        parts.append(combo.key == "Space" ? "Space" : combo.key.uppercased())
        return parts.joined()
    }
}