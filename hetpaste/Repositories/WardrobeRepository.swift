import CloudKit
import Foundation

final class WardrobeRepository {
    private let cloud = CloudKitManager.shared
    func fetchAll(limit: Int = 500) async throws -> [WardrobeItem] { Array(try await cloud.fetchAll(type: CloudRecordType.wardrobeItem, sort: [NSSortDescriptor(key: "createdAt", ascending: false)]).compactMap { try? WardrobeItem(cloudRecord: $0) }.prefix(limit)) }
    func save(_ item: WardrobeItem) async throws -> WardrobeItem {
        var synced = item; let r = synced.cloudRecord(existing: try await cloud.record(type: CloudRecordType.wardrobeItem, id: item.id)); var temp: URL?
        if let data = item.localData, item.contentType != .text, item.contentType != .richText, item.contentType != .url {
            guard data.count <= 50 * 1024 * 1024 else { throw CloudKitPersistenceError.assetTooLarge(Int64(data.count)) }
            let pair = try cloud.asset(from: data, id: item.id); r["asset"] = pair.0; temp = pair.1; synced.storagePath = item.id.uuidString; r["storagePath"] = synced.storagePath
        }
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }; _ = try await cloud.save(r); return synced
    }
    func delete(id: UUID) async throws { try await cloud.delete(type: CloudRecordType.wardrobeItem, id: id) }
    func downloadData(for item: WardrobeItem) async throws -> Data? { guard let r = try await cloud.record(type: CloudRecordType.wardrobeItem, id: item.id), let url = (r["asset"] as? CKAsset)?.fileURL else { return nil }; return try Data(contentsOf: url) }
}
