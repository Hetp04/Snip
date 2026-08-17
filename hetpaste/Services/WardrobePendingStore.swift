import Foundation

/// Durable Wardrobe mutation queue. Stored separately because Wardrobe owns its
/// own view model and may be used before the clipboard library is loaded.
struct WardrobePendingOperations: Codable {
    var saves: [WardrobeItem] = []
    var deletions: Set<UUID> = []
}

final class WardrobePendingStore {
    static let shared = WardrobePendingStore()
    private let url: URL
    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("hetpaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("wardrobe-pending.json")
    }
    func load() -> WardrobePendingOperations { guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(WardrobePendingOperations.self, from: data) else { return .init() }; return value }
    func save(_ value: WardrobePendingOperations) { guard let data = try? JSONEncoder().encode(value) else { return }; try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
}
