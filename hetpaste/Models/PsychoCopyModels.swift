import Foundation
import SwiftUI
struct CopyQueue {
    private(set) var items: [ClipboardItem] = []
    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var preview: [ClipboardItem] { Array(items.prefix(10)) }
    mutating func enqueue(_ item: ClipboardItem) {
        var newItem = item
        newItem.queuePosition = items.count
        newItem.queuedAt = Date()
        items.append(newItem)
    }
    mutating func dequeue() -> ClipboardItem? {
        guard !items.isEmpty else { return nil }
        var item = items.removeFirst()
        item.queuePosition = nil
        item.queuedAt = nil
        for i in 0..<items.count {
            items[i].queuePosition = i
        }
        return item
    }
    mutating func dequeueLast() -> ClipboardItem? {
        guard !items.isEmpty else { return nil }
        var item = items.removeLast()
        item.queuePosition = nil
        item.queuedAt = nil
        return item
    }
    mutating func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        for i in 0..<items.count {
            items[i].queuePosition = i
        }
    }
    mutating func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        for i in 0..<items.count {
            items[i].queuePosition = i
        }
    }
    mutating func clear() {
        items.removeAll()
    }
    func memoryFootprint() -> Int64 {
        items.reduce(0) { total, item in
            total + (item.fileSize ?? Int64(item.localData?.count ?? 0))
        }
    }
}
struct KeyCombination: Codable, Equatable {
    let key: String
    let modifiers: ModifierFlags
    struct ModifierFlags: OptionSet, Codable, Equatable {
        let rawValue: Int
        static let command = ModifierFlags(rawValue: 1 << 0)
        static let option = ModifierFlags(rawValue: 1 << 1)
        static let control = ModifierFlags(rawValue: 1 << 2)
        static let shift = ModifierFlags(rawValue: 1 << 3)
    }
}
struct PsychoCopySettings: Codable {
    var toggleHotkey: KeyCombination = KeyCombination(
        key: "C",
        modifiers: [.command, .option]
    )
    var clearQueueHotkey: KeyCombination = KeyCombination(
        key: "X",
        modifiers: [.command, .option, .shift]
    )
    var reversePasteHotkey: KeyCombination = KeyCombination(
        key: "V",
        modifiers: [.command, .option]
    )
    var searchHotkey: KeyCombination = KeyCombination(
        key: "F",
        modifiers: [.option]
    )
    var showQueuePreview: Bool = true
    var maxQueuePreviewItems: Int = 10
    var memoryWarningThreshold: Int64 = 100_000_000

    // MARK: - Persistence
    private static let userDefaultsKey = "psychoCopySettings"

    static func load() -> PsychoCopySettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(PsychoCopySettings.self, from: data) else {
            return PsychoCopySettings()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: PsychoCopySettings.userDefaultsKey)
        }
    }
}