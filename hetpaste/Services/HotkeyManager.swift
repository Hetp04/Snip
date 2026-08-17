import AppKit
import Carbon
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var registeredHotkeys: [UInt32: () -> Void] = [:]
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var toggleHotkeyID: UInt32 = 1
    private var clearQueueHotkeyID: UInt32 = 2
    private var pasteHotkeyID: UInt32 = 3
    private var reversePasteHotkeyID: UInt32 = 4
    private var searchHotkeyID: UInt32 = 5
    private init() {
        installEventHandler()
    }
    deinit {
        unregisterAllHotkeys()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
    @discardableResult
    func registerToggleHotkey(_ combination: KeyCombination, callback: @escaping () -> Void) -> Bool {
        return registerHotkey(id: toggleHotkeyID, combination: combination, callback: callback)
    }
    @discardableResult
    func registerClearQueueHotkey(_ combination: KeyCombination, callback: @escaping () -> Void) -> Bool {
        return registerHotkey(id: clearQueueHotkeyID, combination: combination, callback: callback)
    }
    @discardableResult
    func registerPasteHotkey(_ combination: KeyCombination, callback: @escaping () -> Void) -> Bool {
        return registerHotkey(id: pasteHotkeyID, combination: combination, callback: callback)
    }
    func unregisterPasteHotkey() {
        if let ref = hotkeyRefs[pasteHotkeyID] {
            UnregisterEventHotKey(ref)
            hotkeyRefs[pasteHotkeyID] = nil
            registeredHotkeys[pasteHotkeyID] = nil
        }
    }
    @discardableResult
    func registerReversePasteHotkey(_ combination: KeyCombination, callback: @escaping () -> Void) -> Bool {
        return registerHotkey(id: reversePasteHotkeyID, combination: combination, callback: callback)
    }
    func unregisterReversePasteHotkey() {
        if let ref = hotkeyRefs[reversePasteHotkeyID] {
            UnregisterEventHotKey(ref)
            hotkeyRefs[reversePasteHotkeyID] = nil
            registeredHotkeys[reversePasteHotkeyID] = nil
        }
    }
    @discardableResult
    func registerSearchHotkey(_ combination: KeyCombination, callback: @escaping () -> Void) -> Bool {
        return registerHotkey(id: searchHotkeyID, combination: combination, callback: callback)
    }
    func unregisterAllHotkeys() {
        for (_, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        registeredHotkeys.removeAll()
    }
    private func registerHotkey(id: UInt32, combination: KeyCombination, callback: @escaping () -> Void) -> Bool {
        if let existingRef = hotkeyRefs[id] {
            UnregisterEventHotKey(existingRef)
            hotkeyRefs[id] = nil
        }
        let keyCode = carbonKeyCode(for: combination.key)
        let modifiers = carbonModifiers(for: combination.modifiers)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType("PCPY".utf8.reduce(0) { $0 << 8 + UInt32($1) }), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            hotkeyRefs[id] = ref
            registeredHotkeys[id] = callback
            return true
        } else {
            print("Failed to register hotkey with id \(id)")
            return false
        }
    }
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                if let callback = HotkeyManager.shared.registeredHotkeys[hotKeyID.id] {
                    DispatchQueue.main.async {
                        callback()
                    }
                    return noErr
                }
            }
            return OSStatus(eventNotHandledErr)
        }
        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventSpec, nil, &eventHandler)
    }
    private func carbonModifiers(for flags: KeyCombination.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        return carbonModifiers
    }
    private func carbonKeyCode(for keyString: String) -> UInt32 {
        let map: [String: Int] = [
            "Space": kVK_Space,
            "C": kVK_ANSI_C,
            "V": kVK_ANSI_V,
            "M": kVK_ANSI_M,
            "Return": kVK_Return,
            "Esc": kVK_Escape
        ]
        if let code = map[keyString] {
            return UInt32(code)
        }
        let upper = keyString.uppercased()
        let charMap: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
            "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
            "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
            "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
            "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
            "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9, "0": kVK_ANSI_0
        ]
        return UInt32(charMap[upper] ?? kVK_Space)
    }
}
