import Foundation
import Supabase

final class WardrobeRepository {
    private var client: SupabaseClient { SupabaseManager.shared.client }
    private let table = "wardrobe_items"
    private let bucket = "wardrobe-items"
    
    // MARK: - Fetch
    
    func fetchAll(limit: Int = 500) async throws -> [WardrobeItem] {
        let records: [WardrobeRecord] = try await client
            .from(table)
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return records.map(WardrobeItem.init(record:))
    }
    
    // MARK: - Save
    
    func save(_ item: WardrobeItem) async throws -> WardrobeItem {
        var synced = item
        
        // Upload file/image data to storage if needed
        if let data = item.localData, item.contentType != .text && item.contentType != .richText && item.contentType != .url {
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
        
        // Insert into table
        try await client
            .from(table)
            .insert(synced.toRecord())
            .execute()
        
        return synced
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) async throws {
        // Fetch item to get storage path
        let records: [WardrobeRecord] = try await client
            .from(table)
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        
        // Delete from storage if it has a file
        if let record = records.first, let storagePath = record.storage_path {
            try? await client.storage
                .from(bucket)
                .remove(paths: [storagePath])
        }
        
        // Delete from table
        try await client
            .from(table)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Download
    
    func downloadData(for item: WardrobeItem) async throws -> Data? {
        guard let path = item.storagePath else { return nil }
        return try await client.storage
            .from(bucket)
            .download(path: path)
    }
    
    // MARK: - Helper
    
    private func storagePath(for item: WardrobeItem) -> String {
        let ext = (item.fileName as NSString?)?.pathExtension ?? ""
        if ext.isEmpty {
            return item.id.uuidString
        }
        return "\(item.id.uuidString).\(ext)"
    }
}
