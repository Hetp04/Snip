import Foundation
import Supabase
final class ClipboardRepository {
    private var client: SupabaseClient { SupabaseManager.shared.client }
    private let table = AppConstants.clipboardTable
    private let foldersTable = AppConstants.foldersTable
    private let snippetFoldersTable = AppConstants.snippetFoldersTable
    func fetchAll(limit: Int = 200) async throws -> [ClipboardItem] {
        let records: [ClipboardRecord] = try await client
            .from(table)
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        var items = records.map(ClipboardItem.init(record:))
        let associations: [SnippetFolderRecord] = try await client
            .from(snippetFoldersTable)
            .select("snippet_id,folder_id")
            .execute()
            .value
        let memberships = Dictionary(grouping: associations) { $0.snippet_id.uppercased() }
        for index in items.indices {
            items[index].folderIDs.formUnion(
                memberships[items[index].id.uuidString, default: []]
                    .compactMap { UUID(uuidString: $0.folder_id) }
            )
        }
        return items
    }
    func save(_ item: ClipboardItem) async throws -> ClipboardItem {
        var synced = item
        if let bucket = item.bucket, let data = item.localData {
            let path = storagePath(for: item)
            try await client.storage
                .from(bucket)
                .upload(
                    path: path,
                    file: data,
                    options: FileOptions(
                        contentType: item.mimeType ?? "application/octet-stream",
                        upsert: true
                    )
                )
            synced.storagePath = path
        }
        try await client
            .from(table)
            .insert(synced.toRecord())
            .execute()
        synced.syncStatus = .synced
        return synced
    }
    func setFavorite(id: UUID, isFavorite: Bool) async throws {
        try await client
            .from(table)
            .update(["is_favorite": isFavorite])
            .eq("id", value: id.uuidString)
            .execute()
    }
    func addToFolder(ids: [UUID], folderID: UUID) async throws {
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await self.client
                        .from(self.snippetFoldersTable)
                        .delete()
                        .eq("snippet_id", value: id.uuidString)
                        .execute()
                }
            }
        }
        
        let records = Set(ids).map {
            SnippetFolderInsertRecord(snippet_id: $0.uuidString, folder_id: folderID.uuidString)
        }
        guard !records.isEmpty else { return }
        try await client
            .from(snippetFoldersTable)
            .upsert(records, onConflict: "snippet_id,folder_id")
            .execute()
    }
    func removeFromFolder(id: UUID, folderID: UUID) async throws {
        try await client
            .from(snippetFoldersTable)
            .delete()
            .eq("snippet_id", value: id.uuidString)
            .eq("folder_id", value: folderID.uuidString)
            .execute()
    }
    func delete(id: UUID) async throws {
        try await client
            .from(table)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    func downloadData(for item: ClipboardItem) async throws -> Data? {
        guard let bucket = item.bucket, let path = item.storagePath else { return nil }
        return try await client.storage
            .from(bucket)
            .download(path: path)
    }
    func fetchFolders() async throws -> [ClipboardFolder] {
        let records: [ClipboardFolderRecord] = try await client
            .from(foldersTable)
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value
        return records.map(ClipboardFolder.init(record:))
    }
    func createFolder(id: UUID, name: String) async throws {
        try await client
            .from(foldersTable)
            .insert(ClipboardFolderInsertRecord(id: id.uuidString, name: name))
            .execute()
    }
    func renameFolder(id: UUID, name: String) async throws {
        try await client
            .from(foldersTable)
            .update(ClipboardFolderNameUpdate(name: name))
            .eq("id", value: id.uuidString)
            .execute()
    }
    func deleteFolder(id: UUID) async throws {
        try await client
            .from(foldersTable)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    private func storagePath(for item: ClipboardItem) -> String {
        let ext = (item.fileName as NSString?)?.pathExtension ?? ""
        if ext.isEmpty {
            return item.id.uuidString
        }
        return "\(item.id.uuidString).\(ext)"
    }
    
    // MARK: - Chains
    
    func fetchChains() async throws -> [Chain] {
        let records: [ChainRecord] = try await client
            .from(AppConstants.chainsTable)
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value
        return records.map(Chain.init(record:))
    }
    
    func fetchChainItems(chainID: UUID) async throws -> [ChainItem] {
        let records: [ChainItemRecord] = try await client
            .from(AppConstants.chainItemsTable)
            .select()
            .eq("chain_id", value: chainID.uuidString)
            .order("position", ascending: true)
            .execute()
            .value
        return records.map(ChainItem.init(record:))
    }
    
    func createChain(id: UUID, name: String) async throws {
        try await client
            .from(AppConstants.chainsTable)
            .insert(ChainInsertRecord(id: id.uuidString, name: name))
            .execute()
    }
    
    func addChainItems(_ items: [ChainItem], chainID: UUID) async throws {
        guard !items.isEmpty else { return }
        let records = items.map {
            ChainItemInsertRecord(
                id: $0.id.uuidString,
                chain_id: chainID.uuidString,
                snippet_id: $0.snippetID.uuidString,
                position: $0.position
            )
        }
        try await client
            .from(AppConstants.chainItemsTable)
            .insert(records)
            .execute()
    }
    
    func renameChain(id: UUID, name: String) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAt = formatter.string(from: Date())
        try await client
            .from(AppConstants.chainsTable)
            .update(ChainNameUpdate(name: name, updated_at: updatedAt))
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    func deleteChainItems(chainID: UUID) async throws {
        try await client
            .from(AppConstants.chainItemsTable)
            .delete()
            .eq("chain_id", value: chainID.uuidString)
            .execute()
    }
    
    func deleteChain(id: UUID) async throws {
        try await client
            .from(AppConstants.chainsTable)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}