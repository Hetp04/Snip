import CloudKit
import Foundation
import SQLite3

/// On-device metadata index for the clipboard library. Binary assets stay in
/// `AssetCache`; CloudKit remains the source of truth. SQLite gives launch and
/// scrolling a bounded cost instead of decoding and rewriting one ever-growing
/// JSON document.
// All SQLite access is serialized with `lock`; callers may safely issue read
// queries from a background task without touching SwiftUI's main actor.
final class LibraryMetadataStore: @unchecked Sendable {
    static let shared = LibraryMetadataStore()

    struct QueueState: Codable {
        var pendingItemIDs: Set<UUID> = []
        var pendingFolderIDs: Set<UUID> = []
        var pendingDeletionIDs: Set<UUID> = []
        var pendingFolderDeletionIDs: Set<UUID> = []
        var pendingChainIDs: Set<UUID> = []
        var pendingChainDeletionIDs: Set<UUID> = []
    }

    struct InitialLibrary {
        var items: [ClipboardItem]
        var folders: [ClipboardFolder]
        var chains: [Chain]
        var chainItems: [UUID: [ChainItem]]
        var queues: QueueState
        var hasMoreItems: Bool
    }

    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var database: OpaquePointer?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("hetpaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library-metadata.sqlite")
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            database = nil
            return
        }
        _ = execute("PRAGMA journal_mode=WAL;")
        _ = execute("PRAGMA synchronous=NORMAL;")
        _ = execute("PRAGMA foreign_keys=ON;")
        _ = execute("""
        CREATE TABLE IF NOT EXISTS records (
            kind TEXT NOT NULL,
            id TEXT NOT NULL,
            created_at REAL NOT NULL,
            search_text TEXT NOT NULL DEFAULT '',
            is_deleted INTEGER NOT NULL DEFAULT 0,
            folder_ids TEXT NOT NULL DEFAULT '',
            payload BLOB NOT NULL,
            PRIMARY KEY(kind, id)
        );
        CREATE INDEX IF NOT EXISTS records_kind_created ON records(kind, created_at DESC);
        CREATE INDEX IF NOT EXISTS records_item_search ON records(kind, is_deleted, search_text);
        CREATE TABLE IF NOT EXISTS state (
            key TEXT PRIMARY KEY,
            payload BLOB NOT NULL
        );
        """)
        // Existing installations may have been created by an earlier build of
        // this store. Check first so normal launches do not log duplicate
        // column errors for a completed migration.
        addColumnIfMissing("search_text", definition: "TEXT NOT NULL DEFAULT ''")
        addColumnIfMissing("is_deleted", definition: "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("folder_ids", definition: "TEXT NOT NULL DEFAULT ''")
        _ = execute("CREATE INDEX IF NOT EXISTS records_item_search ON records(kind, is_deleted, search_text);")
        migrateLegacySnapshotIfNeeded()
        rebuildItemIndexesIfNeeded()
    }

    deinit { if let database { sqlite3_close(database) } }

    func loadInitial(itemLimit: Int) -> InitialLibrary {
        lock.lock(); defer { lock.unlock() }
        let queues = loadQueuesLocked()
        let items = fetchItemsLocked(olderThan: nil, afterID: nil, limit: itemLimit)
            .filter { !queues.pendingDeletionIDs.contains($0.id) }
        let folders = fetchLocked(kind: "folder", as: ClipboardFolder.self)
            .filter { !queues.pendingFolderDeletionIDs.contains($0.id) }
        let chains = fetchLocked(kind: "chain", as: Chain.self)
            .filter { !queues.pendingChainDeletionIDs.contains($0.id) }
        let allChainItems = fetchLocked(kind: "chainItem", as: ChainItem.self)
        let byChain = Dictionary(grouping: allChainItems, by: \.chainID)
        return InitialLibrary(
            items: items,
            folders: folders,
            chains: chains,
            chainItems: byChain,
            queues: queues,
            hasMoreItems: countLocked(kind: "item") > items.count
        )
    }

    func loadItems(olderThan date: Date?, afterID: UUID?, limit: Int) -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        let queues = loadQueuesLocked()
        return fetchItemsLocked(olderThan: date, afterID: afterID, limit: limit)
            .filter { !queues.pendingDeletionIDs.contains($0.id) }
    }

    func searchItems(matching query: String, limit: Int = 200) -> [ClipboardItem] {
        let terms = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        lock.lock(); defer { lock.unlock() }
        let queues = loadQueuesLocked()
        let predicates = Array(repeating: "search_text LIKE ?", count: terms.count).joined(separator: " AND ")
        let sql = "SELECT payload FROM records WHERE kind = 'item' AND is_deleted = 0 AND \(predicates) ORDER BY created_at DESC, id DESC LIMIT ?;"
        var results: [ClipboardItem] = []
        withStatement(sql) { statement in
            for (offset, term) in terms.enumerated() { bind("%\(term)%", to: statement, index: Int32(offset + 1)) }
            sqlite3_bind_int(statement, Int32(terms.count + 1), Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                if let item = try? decoder.decode(ClipboardItem.self, from: data), !queues.pendingDeletionIDs.contains(item.id) {
                    results.append(item)
                }
            }
        }
        return results
    }

    func itemCount(inFolder folderID: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        let queues = loadQueuesLocked()
        var count = 0
        withStatement("SELECT COUNT(*) FROM records WHERE kind = 'item' AND is_deleted = 0 AND folder_ids LIKE ?;") { statement in
            bind("%|\(folderID.uuidString.lowercased())|%", to: statement, index: 1)
            if sqlite3_step(statement) == SQLITE_ROW { count = Int(sqlite3_column_int64(statement, 0)) }
        }
        // A queued permanent delete was removed from the index immediately;
        // this filter also handles migration-era rows defensively.
        return count - queues.pendingDeletionIDs.reduce(0) { partial, id in
            partial + (folderContainsLocked(itemID: id, folderID: folderID) ? 1 : 0)
        }
    }

    func historyItemCount(in range: ClipboardHistoryRange) -> Int {
        lock.lock(); defer { lock.unlock() }
        let bounds = range.bounds()
        var count = 0
        withStatement(historyRangeSQL(select: "COUNT(*)", bounds: bounds)) { statement in
            bindHistoryBounds(bounds, to: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(statement, 0))
            }
        }
        return count
    }

    func historyItemIDs(in range: ClipboardHistoryRange) -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let bounds = range.bounds()
        var ids = Set<UUID>()
        withStatement(historyRangeSQL(select: "id", bounds: bounds)) { statement in
            bindHistoryBounds(bounds, to: statement)
            while sqlite3_step(statement) == SQLITE_ROW,
                  let raw = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: raw)) {
                ids.insert(id)
            }
        }
        return ids
    }

    private func historyRangeSQL(
        select: String,
        bounds: (start: Date?, end: Date?)
    ) -> String {
        var clauses = ["kind = 'item'"]
        if bounds.start != nil { clauses.append("created_at >= ?") }
        if bounds.end != nil { clauses.append("created_at <= ?") }
        return "SELECT \(select) FROM records WHERE \(clauses.joined(separator: " AND "));"
    }

    private func bindHistoryBounds(
        _ bounds: (start: Date?, end: Date?),
        to statement: OpaquePointer?
    ) {
        var index: Int32 = 1
        if let start = bounds.start {
            sqlite3_bind_double(statement, index, start.timeIntervalSince1970)
            index += 1
        }
        if let end = bounds.end {
            sqlite3_bind_double(statement, index, end.timeIntervalSince1970)
        }
    }

    func upsert(items: [ClipboardItem] = [], folders: [ClipboardFolder] = [], chains: [Chain] = [], chainItems: [ChainItem] = [], queues: QueueState? = nil) {
        lock.lock(); defer { lock.unlock() }
        _ = execute("BEGIN IMMEDIATE TRANSACTION;")
        defer { _ = execute("COMMIT;") }
        for item in items { upsertItemLocked(item.withoutLocalPayload) }
        for folder in folders { upsertLocked(kind: "folder", id: folder.id, createdAt: folder.createdAt, value: folder) }
        for chain in chains { upsertLocked(kind: "chain", id: chain.id, createdAt: chain.createdAt, value: chain) }
        for chainItem in chainItems { upsertLocked(kind: "chainItem", id: chainItem.id, createdAt: Date(timeIntervalSince1970: TimeInterval(chainItem.position)), value: chainItem) }
        if let queues { saveQueuesLocked(queues) }
    }

    func remove(items: Set<UUID> = [], folders: Set<UUID> = [], chains: Set<UUID> = []) {
        lock.lock(); defer { lock.unlock() }
        _ = execute("BEGIN IMMEDIATE TRANSACTION;")
        defer { _ = execute("COMMIT;") }
        for id in items { deleteLocked(kind: "item", id: id) }
        for id in folders { deleteLocked(kind: "folder", id: id) }
        for id in chains {
            deleteLocked(kind: "chain", id: id)
            deleteChainItemsLocked(chainID: id)
        }
    }

    func saveQueues(_ queues: QueueState) {
        lock.lock(); defer { lock.unlock() }
        saveQueuesLocked(queues)
    }

    func needsInitialRemoteBootstrap() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loadStateLocked(key: "initial-remote-bootstrap-v1", as: Bool.self) != true
    }

    func markInitialRemoteBootstrapComplete() {
        lock.lock(); defer { lock.unlock() }
        saveStateLocked(true, key: "initial-remote-bootstrap-v1")
    }

    /// A private CloudKit database is scoped to the signed-in Apple Account.
    /// Never reuse a cache or a server-change token after that identity changes.
    func resetIfAccountChanged(to accountIdentifier: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let previous = loadStateLocked(key: "cloudkit-account-id-v1", as: String.self)
        guard previous != accountIdentifier else { return false }
        _ = execute("BEGIN IMMEDIATE TRANSACTION;")
        _ = execute("DELETE FROM records;")
        _ = execute("DELETE FROM state;")
        saveStateLocked(true, key: "metadata-store-migrated-v1")
        saveStateLocked(accountIdentifier, key: "cloudkit-account-id-v1")
        _ = execute("COMMIT;")
        return true
    }

    /// Applies one CloudKit zone change directly to the local metadata index.
    /// Pending local mutations win until their durable queue is resolved.
    func applyRemoteRecord(_ record: CKRecord) {
        lock.lock(); defer { lock.unlock() }
        applyRemoteRecordLocked(record, queues: loadQueuesLocked())
    }

    func applyRemoteRecords(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let queues = loadQueuesLocked()
        _ = execute("BEGIN IMMEDIATE TRANSACTION;")
        defer { _ = execute("COMMIT;") }
        for record in records { applyRemoteRecordLocked(record, queues: queues) }
    }

    private func applyRemoteRecordLocked(_ record: CKRecord, queues: QueueState) {
        switch record.recordType {
        case CloudRecordType.clipboardItem:
            guard let item = try? ClipboardItem(cloudRecord: record), !queues.pendingItemIDs.contains(item.id) else { return }
            upsertItemLocked(item.withoutLocalPayload)
        case CloudRecordType.folder:
            guard let folder = try? ClipboardFolder(cloudRecord: record), !queues.pendingFolderIDs.contains(folder.id) else { return }
            upsertLocked(kind: "folder", id: folder.id, createdAt: folder.createdAt, value: folder)
        case CloudRecordType.chain:
            guard let chain = try? Chain(cloudRecord: record), !queues.pendingChainIDs.contains(chain.id) else { return }
            upsertLocked(kind: "chain", id: chain.id, createdAt: chain.createdAt, value: chain)
        case CloudRecordType.chainItem:
            guard let item = try? ChainItem(cloudRecord: record), !queues.pendingChainIDs.contains(item.chainID) else { return }
            upsertLocked(kind: "chainItem", id: item.id, createdAt: Date(timeIntervalSince1970: TimeInterval(item.position)), value: item)
        default:
            break
        }
    }

    func applyRemoteDeletion(_ recordID: CKRecord.ID) {
        applyRemoteDeletions([recordID])
    }

    func applyRemoteDeletions(_ recordIDs: [CKRecord.ID]) {
        guard !recordIDs.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var queues = loadQueuesLocked()
        _ = execute("BEGIN IMMEDIATE TRANSACTION;")
        defer { _ = execute("COMMIT;") }
        for recordID in recordIDs { applyRemoteDeletionLocked(recordID, queues: &queues) }
        saveQueuesLocked(queues)
    }

    private func applyRemoteDeletionLocked(_ recordID: CKRecord.ID, queues: inout QueueState) {
        let parts = recordID.recordName.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return }
        switch parts[0] {
        case CloudRecordType.clipboardItem:
            // A confirmed server deletion is authoritative. Cancel any stale
            // offline edit so another device cannot recreate this record.
            queues.pendingItemIDs.remove(id)
            queues.pendingDeletionIDs.remove(id)
            deleteLocked(kind: "item", id: id)
        case CloudRecordType.folder:
            queues.pendingFolderIDs.remove(id)
            queues.pendingFolderDeletionIDs.remove(id)
            deleteLocked(kind: "folder", id: id)
        case CloudRecordType.chain:
            queues.pendingChainIDs.remove(id)
            queues.pendingChainDeletionIDs.remove(id)
            deleteLocked(kind: "chain", id: id)
            deleteChainItemsLocked(chainID: id)
        case CloudRecordType.chainItem:
            deleteLocked(kind: "chainItem", id: id)
        default:
            break
        }
    }

    private func migrateLegacySnapshotIfNeeded() {
        guard loadStateLocked(key: "metadata-store-migrated-v1", as: Bool.self) != true else { return }
        if let snapshot = LibraryCache.shared.load() {
            let queues = QueueState(
                pendingItemIDs: snapshot.pendingItemIDs,
                pendingFolderIDs: snapshot.pendingFolderIDs,
                pendingDeletionIDs: snapshot.pendingDeletionIDs,
                pendingFolderDeletionIDs: snapshot.pendingFolderDeletionIDs,
                pendingChainIDs: snapshot.pendingChainIDs,
                pendingChainDeletionIDs: snapshot.pendingChainDeletionIDs
            )
            upsert(
                items: snapshot.items,
                folders: snapshot.folders,
                chains: snapshot.chains,
                chainItems: snapshot.chainItems.values.flatMap { $0 },
                queues: queues
            )
        }
        saveStateLocked(true, key: "metadata-store-migrated-v1")
    }

    private func rebuildItemIndexesIfNeeded() {
        guard loadStateLocked(key: "metadata-store-item-index-v1", as: Bool.self) != true else { return }
        let items = fetchLocked(kind: "item", as: ClipboardItem.self)
        _ = execute("BEGIN IMMEDIATE TRANSACTION;")
        for item in items { upsertItemLocked(item.withoutLocalPayload) }
        _ = execute("COMMIT;")
        saveStateLocked(true, key: "metadata-store-item-index-v1")
    }

    private func loadQueuesLocked() -> QueueState {
        loadStateLocked(key: "queues-v1", as: QueueState.self) ?? QueueState()
    }

    private func saveQueuesLocked(_ queues: QueueState) { saveStateLocked(queues, key: "queues-v1") }

    private func upsertLocked<Value: Encodable>(kind: String, id: UUID, createdAt: Date, value: Value) {
        guard let data = try? encoder.encode(value) else { return }
        withStatement("INSERT INTO records(kind, id, created_at, payload) VALUES(?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET created_at = excluded.created_at, payload = excluded.payload;") { statement in
            bind(kind, to: statement, index: 1)
            bind(id.uuidString.lowercased(), to: statement, index: 2)
            sqlite3_bind_double(statement, 3, createdAt.timeIntervalSince1970)
            bind(data, to: statement, index: 4)
            _ = sqlite3_step(statement)
        }
    }

    private func upsertItemLocked(_ item: ClipboardItem) {
        guard let data = try? encoder.encode(item) else { return }
        let searchable = [item.contentText, item.searchContext, item.sourceAppName, item.fileName, item.detectedLanguage]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let folderIDs = item.folderIDs.map { "|\($0.uuidString.lowercased())|" }.joined()
        withStatement("INSERT INTO records(kind, id, created_at, search_text, is_deleted, folder_ids, payload) VALUES('item', ?, ?, ?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET created_at = excluded.created_at, search_text = excluded.search_text, is_deleted = excluded.is_deleted, folder_ids = excluded.folder_ids, payload = excluded.payload;") { statement in
            bind(item.id.uuidString.lowercased(), to: statement, index: 1)
            sqlite3_bind_double(statement, 2, item.createdAt.timeIntervalSince1970)
            bind(searchable, to: statement, index: 3)
            sqlite3_bind_int(statement, 4, item.isDeleted ? 1 : 0)
            bind(folderIDs, to: statement, index: 5)
            bind(data, to: statement, index: 6)
            _ = sqlite3_step(statement)
        }
    }

    private func folderContainsLocked(itemID: UUID, folderID: UUID) -> Bool {
        var exists = false
        withStatement("SELECT 1 FROM records WHERE kind = 'item' AND id = ? AND folder_ids LIKE ? LIMIT 1;") { statement in
            bind(itemID.uuidString.lowercased(), to: statement, index: 1)
            bind("%|\(folderID.uuidString.lowercased())|%", to: statement, index: 2)
            exists = sqlite3_step(statement) == SQLITE_ROW
        }
        return exists
    }

    private func fetchLocked<Value: Decodable>(kind: String, limit: Int? = nil, offset: Int = 0, as: Value.Type) -> [Value] {
        let sql: String
        if limit != nil { sql = "SELECT payload FROM records WHERE kind = ? ORDER BY created_at DESC LIMIT ? OFFSET ?;" }
        else { sql = "SELECT payload FROM records WHERE kind = ? ORDER BY created_at DESC;" }
        var result: [Value] = []
        withStatement(sql) { statement in
            bind(kind, to: statement, index: 1)
            if let limit {
                sqlite3_bind_int(statement, 2, Int32(limit))
                sqlite3_bind_int(statement, 3, Int32(offset))
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                let count = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: bytes, count: count)
                if let value = try? decoder.decode(Value.self, from: data) { result.append(value) }
            }
        }
        return result
    }

    private func fetchItemsLocked(olderThan date: Date?, afterID: UUID?, limit: Int) -> [ClipboardItem] {
        let sql = date == nil
            ? "SELECT payload FROM records WHERE kind = 'item' ORDER BY created_at DESC, id DESC LIMIT ?;"
            : "SELECT payload FROM records WHERE kind = 'item' AND (created_at < ? OR (created_at = ? AND id < ?)) ORDER BY created_at DESC, id DESC LIMIT ?;"
        var result: [ClipboardItem] = []
        withStatement(sql) { statement in
            if let date {
                sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
                bind(afterID?.uuidString.lowercased() ?? "", to: statement, index: 3)
                sqlite3_bind_int(statement, 4, Int32(limit))
            } else {
                sqlite3_bind_int(statement, 1, Int32(limit))
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                if let value = try? decoder.decode(ClipboardItem.self, from: data) { result.append(value) }
            }
        }
        return result
    }

    private func deleteLocked(kind: String, id: UUID) {
        withStatement("DELETE FROM records WHERE kind = ? AND id = ?;") { statement in
            bind(kind, to: statement, index: 1)
            bind(id.uuidString.lowercased(), to: statement, index: 2)
            _ = sqlite3_step(statement)
        }
    }

    private func deleteChainItemsLocked(chainID: UUID) {
        let entries = fetchLocked(kind: "chainItem", as: ChainItem.self).filter { $0.chainID == chainID }
        for entry in entries { deleteLocked(kind: "chainItem", id: entry.id) }
    }

    private func countLocked(kind: String) -> Int {
        var count = 0
        withStatement("SELECT COUNT(*) FROM records WHERE kind = ?;") { statement in
            bind(kind, to: statement, index: 1)
            if sqlite3_step(statement) == SQLITE_ROW { count = Int(sqlite3_column_int64(statement, 0)) }
        }
        return count
    }

    private func saveStateLocked<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        withStatement("INSERT INTO state(key, payload) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET payload = excluded.payload;") { statement in
            bind(key, to: statement, index: 1)
            bind(data, to: statement, index: 2)
            _ = sqlite3_step(statement)
        }
    }

    private func loadStateLocked<Value: Decodable>(key: String, as: Value.Type) -> Value? {
        var result: Value?
        withStatement("SELECT payload FROM state WHERE key = ?;") { statement in
            bind(key, to: statement, index: 1)
            guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            result = try? decoder.decode(Value.self, from: data)
        }
        return result
    }

    private func execute(_ sql: String) -> Bool {
        guard let database else { return false }
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func addColumnIfMissing(_ name: String, definition: String) {
        var exists = false
        withStatement("PRAGMA table_info(records);") { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let value = sqlite3_column_text(statement, 1) else { continue }
                if String(cString: value) == name { exists = true; break }
            }
        }
        guard !exists else { return }
        _ = execute("ALTER TABLE records ADD COLUMN \(name) \(definition);")
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) -> Void) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        body(statement)
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bind(_ value: Data, to statement: OpaquePointer, index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension ClipboardItem {
    var withoutLocalPayload: ClipboardItem {
        var value = self
        value.localData = nil
        value.rawPasteboardData = nil
        value.originalFileURL = nil
        return value
    }
}
