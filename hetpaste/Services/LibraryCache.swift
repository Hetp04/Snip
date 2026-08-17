import Foundation

/// A private, on-device snapshot of the library. It is a responsiveness and
/// offline fallback only; CloudKit remains the authoritative data source.
struct LibrarySnapshot: Codable {
    var items: [ClipboardItem]
    var folders: [ClipboardFolder]
    var chains: [Chain]
    var chainItems: [UUID: [ChainItem]]
    var pendingItemIDs: Set<UUID>
    var pendingFolderIDs: Set<UUID>
    var pendingDeletionIDs: Set<UUID>
    var pendingFolderDeletionIDs: Set<UUID>
    var pendingChainIDs: Set<UUID>
    var pendingChainDeletionIDs: Set<UUID>
    var savedAt: Date

    private enum CodingKeys: String, CodingKey { case items, folders, chains, chainItems, pendingItemIDs, pendingFolderIDs, pendingDeletionIDs, pendingFolderDeletionIDs, pendingChainIDs, pendingChainDeletionIDs, savedAt }

    init(items: [ClipboardItem], folders: [ClipboardFolder], chains: [Chain], chainItems: [UUID: [ChainItem]], pendingItemIDs: Set<UUID>, pendingFolderIDs: Set<UUID>, pendingDeletionIDs: Set<UUID>, pendingFolderDeletionIDs: Set<UUID> = [], pendingChainIDs: Set<UUID> = [], pendingChainDeletionIDs: Set<UUID> = [], savedAt: Date) {
        self.items = items; self.folders = folders; self.chains = chains; self.chainItems = chainItems
        self.pendingItemIDs = pendingItemIDs; self.pendingFolderIDs = pendingFolderIDs; self.pendingDeletionIDs = pendingDeletionIDs; self.pendingFolderDeletionIDs = pendingFolderDeletionIDs; self.pendingChainIDs = pendingChainIDs; self.pendingChainDeletionIDs = pendingChainDeletionIDs; self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([ClipboardItem].self, forKey: .items)
        folders = try c.decode([ClipboardFolder].self, forKey: .folders)
        chains = try c.decode([Chain].self, forKey: .chains)
        chainItems = try c.decode([UUID: [ChainItem]].self, forKey: .chainItems)
        pendingItemIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingItemIDs) ?? []
        pendingFolderIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingFolderIDs) ?? []
        pendingDeletionIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingDeletionIDs) ?? []
        pendingFolderDeletionIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingFolderDeletionIDs) ?? []
        pendingChainIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingChainIDs) ?? []
        pendingChainDeletionIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingChainDeletionIDs) ?? []
        savedAt = try c.decode(Date.self, forKey: .savedAt)
    }
}

final class LibraryCache {
    static let shared = LibraryCache()
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(fileManager: FileManager = .default) {
        let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("hetpaste", isDirectory: true)
        if let directory { try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        self.fileURL = (directory ?? fileManager.temporaryDirectory).appendingPathComponent("library-cache.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(LibrarySnapshot.self, from: data)
    }

    func save(items: [ClipboardItem], folders: [ClipboardFolder], chains: [Chain], chainItems: [UUID: [ChainItem]], pendingItemIDs: Set<UUID>, pendingFolderIDs: Set<UUID>, pendingDeletionIDs: Set<UUID>, pendingFolderDeletionIDs: Set<UUID> = [], pendingChainIDs: Set<UUID> = [], pendingChainDeletionIDs: Set<UUID> = []) {
        // Assets live in CloudKit. Avoid duplicating potentially large copied
        // files locally while still keeping all cards/folders usable offline.
        let cachedItems = items.map { item -> ClipboardItem in
            var item = item
            item.localData = nil
            item.rawPasteboardData = nil
            item.originalFileURL = nil
            return item
        }
        let snapshot = LibrarySnapshot(items: cachedItems, folders: folders, chains: chains, chainItems: chainItems, pendingItemIDs: pendingItemIDs, pendingFolderIDs: pendingFolderIDs, pendingDeletionIDs: pendingDeletionIDs, pendingFolderDeletionIDs: pendingFolderDeletionIDs, pendingChainIDs: pendingChainIDs, pendingChainDeletionIDs: pendingChainDeletionIDs, savedAt: Date())
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
