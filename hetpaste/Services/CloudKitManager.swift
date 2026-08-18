import CloudKit
import Foundation

struct CloudBatchDeletionFailure: Error {
    let deletedRecordIDs: Set<CKRecord.ID>
    let underlyingError: Error
}

/// A persistent cache for `CKRecord` instances waiting to be uploaded by `CKSyncEngine`.
final class PendingRecordStore {
    static let shared = PendingRecordStore()
    
    private let fileURL: URL
    private var records: [CKRecord.ID: CKRecord] = [:]
    private let lock = NSLock()
    
    private init() {
        let fileManager = FileManager.default
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("hetpaste", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pending-sync-records.data")
        
        loadLocked()
    }
    
    func store(_ record: CKRecord) {
        lock.lock(); defer { lock.unlock() }
        records[record.recordID] = record
        persistLocked()
    }
    
    func remove(id: CKRecord.ID) {
        lock.lock(); defer { lock.unlock() }
        records.removeValue(forKey: id)
        persistLocked()
    }
    
    func record(for id: CKRecord.ID) -> CKRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[id]
    }
    
    private func loadLocked() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, CKRecord.self, CKRecord.ID.self, NSString.self], from: data) as? [CKRecord.ID: CKRecord] else {
            return
        }
        records = dict
    }
    
    private func persistLocked() {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: records, requiringSecureCoding: true) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// The single entry point for the user's private iCloud clipboard library.
/// Stable UUIDs are used as CloudKit record names so models never depend on
/// temporary CKRecord instances. 
@available(macOS 14.0, *)
final class CloudKitManager: @unchecked Sendable, CKSyncEngineDelegate {
    static let shared = CloudKitManager()

    let container: CKContainer
    let database: CKDatabase
    let libraryZoneID = CKRecordZone.ID(zoneName: "ClipboardLibrary")
    
    private(set) var engine: CKSyncEngine!
    private let stateKey = "cloudkit.engine.state"
    
    // Callbacks to pipe data back to LibraryMetadataStore
    var onRecordsChanged: (([CKRecord]) -> Void)?
    var onRecordsDeleted: (([CKRecord.ID]) -> Void)?
    
    private init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
    }
    
    func start() async throws {
        // Initialize the zone
        _ = try? await database.modifyRecordZones(saving: [CKRecordZone(zoneID: libraryZoneID)], deleting: [])
        
        let stateData = UserDefaults.standard.data(forKey: stateKey)
        let state = stateData.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        
        let config = CKSyncEngine.Configuration(
            database: self.database,
            stateSerialization: state,
            delegate: self
        )
        self.engine = CKSyncEngine(config)
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateEvent):
            if let data = try? JSONEncoder().encode(stateEvent.stateSerialization) {
                UserDefaults.standard.set(data, forKey: stateKey)
            }
        case .fetchedRecordZoneChanges(let fetchEvent):
            let modifications = fetchEvent.modifications.map { $0.record }
            let deletions = fetchEvent.deletions.map { $0.recordID }
            if !modifications.isEmpty { onRecordsChanged?(modifications) }
            if !deletions.isEmpty { onRecordsDeleted?(deletions) }
        case .sentRecordZoneChanges(let sentEvent):
            for record in sentEvent.savedRecords {
                PendingRecordStore.shared.remove(id: record.recordID)
            }
            for deletion in sentEvent.deletedRecordIDs {
                PendingRecordStore.shared.remove(id: deletion)
            }
            for failed in sentEvent.failedRecordSaves {
                if let ckError = failed.error as? CKError, ckError.code == .serverRecordChanged, let serverRecord = ckError.serverRecord {
                    // Conflict resolution: last writer wins
                    let local = failed.record
                    let localUpdatedAt = local["updatedAt"] as? Date ?? local.modificationDate ?? .distantPast
                    let serverUpdatedAt = serverRecord["updatedAt"] as? Date ?? serverRecord.modificationDate ?? .distantPast
                    
                    if localUpdatedAt > serverUpdatedAt {
                        // Re-save local
                        engine.state.add(pendingRecordZoneChanges: [.saveRecord(local.recordID)])
                    }
                }
            }
        case .accountChange:
            // Clear local state if needed
            UserDefaults.standard.removeObject(forKey: stateKey)
        default:
            break
        }
    }
    
    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        var modifications = [CKRecord]()
        var deletions = [CKRecord.ID]()
        
        for change in engine.state.pendingRecordZoneChanges {
            switch change {
            case .saveRecord(let id):
                if let record = PendingRecordStore.shared.record(for: id) {
                    modifications.append(record)
                }
            case .deleteRecord(let id):
                deletions.append(id)
            @unknown default:
                break
            }
        }
        
        if modifications.isEmpty && deletions.isEmpty { return nil }
        
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: modifications,
            recordIDsToDelete: deletions,
            atomicByZone: false
        )
    }

    func verifyAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw CloudKitPersistenceError.accountUnavailable(status) }
    }

    func record(type: String, id: UUID) async throws -> CKRecord? {
        try await record(type: type, recordName: "\(type).\(id.uuidString.lowercased())")
    }

    func record(type: String, recordName: String) async throws -> CKRecord? {
        try await verifyAccount()
        do { return try await database.record(for: recordID(type: type, recordName: recordName)) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    func save(_ record: CKRecord) {
        PendingRecordStore.shared.store(record)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
    }

    func delete(type: String, id: UUID) {
        delete(type: type, recordName: "\(type).\(id.uuidString.lowercased())")
    }

    func delete(type: String, recordName: String) {
        let id = recordID(type: type, recordName: recordName)
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
    }

    func fetchAll(type: String, sort: [NSSortDescriptor] = []) async throws -> [CKRecord] {
        try await verifyAccount()
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var result: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor { page = try await database.records(continuingMatchFrom: cursor) }
            else { page = try await database.records(matching: query, inZoneWith: libraryZoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) }
            for (_, value) in page.matchResults { result.append(try value.get()) }
            cursor = page.queryCursor
        } while cursor != nil
        guard let descriptor = sort.first, let key = descriptor.key else { return result }
        return result.sorted { lhs, rhs in
            let left = lhs[key] as? Date
            let right = rhs[key] as? Date
            let ascending = descriptor.ascending
            switch (left, right) {
            case let (left?, right?): return ascending ? left < right : left > right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
    }

    func fetchFirstPage(type: String, sort: NSSortDescriptor, limit: Int) async throws -> [CKRecord] {
        try await verifyAccount()
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        query.sortDescriptors = [sort]
        let page = try await database.records(
            matching: query,
            inZoneWith: libraryZoneID,
            desiredKeys: nil,
            resultsLimit: limit
        )
        return try page.matchResults.map { try $0.1.get() }
    }

    func deleteAll(type: String, matching predicate: NSPredicate) async throws {
        try await verifyAccount()
        let query = CKQuery(recordType: type, predicate: predicate)
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor { page = try await database.records(continuingMatchFrom: cursor) }
            else { page = try await database.records(matching: query, inZoneWith: libraryZoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) }
            for (id, value) in page.matchResults {
                _ = try value.get()
                delete(recordID: id)
            }
            cursor = page.queryCursor
        } while cursor != nil
    }

    func deleteMatchingRecords(
        type: String,
        predicate: NSPredicate,
        batchSize: Int = 200,
        progress: (@Sendable (_ deleted: Int) -> Void)? = nil
    ) async throws -> Set<CKRecord.ID> {
        try await verifyAccount()
        let query = CKQuery(recordType: type, predicate: predicate)
        var cursor: CKQueryOperation.Cursor?
        var deleted = Set<CKRecord.ID>()

        do {
            repeat {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor)
                } else {
                    page = try await database.records(
                        matching: query,
                        inZoneWith: libraryZoneID,
                        desiredKeys: [],
                        resultsLimit: batchSize
                    )
                }

                let recordIDs = try page.matchResults.map { id, result in
                    _ = try result.get()
                    return id
                }

                for id in recordIDs {
                    delete(recordID: id)
                    deleted.insert(id)
                }
                progress?(deleted.count)
                cursor = page.queryCursor
            } while cursor != nil
            return deleted
        } catch {
            if deleted.isEmpty { throw error }
            throw CloudBatchDeletionFailure(deletedRecordIDs: deleted, underlyingError: error)
        }
    }
    
    func delete(recordID: CKRecord.ID) {
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    func recordID(type: String, id: UUID) -> CKRecord.ID {
        recordID(type: type, recordName: "\(type).\(id.uuidString.lowercased())")
    }

    func recordID(type: String, recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: libraryZoneID)
    }

    func records(matching query: CKQuery, limit: Int = CKQueryOperation.maximumResults) async throws -> [(CKRecord.ID, Result<CKRecord, Error>)] {
        try await verifyAccount()
        var all: [(CKRecord.ID, Result<CKRecord, Error>)] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor)
            } else {
                page = try await database.records(matching: query, inZoneWith: libraryZoneID, desiredKeys: nil, resultsLimit: limit)
            }
            all.append(contentsOf: page.matchResults)
            cursor = page.queryCursor
        } while cursor != nil
        return all
    }

    func asset(from data: Data, id: UUID) throws -> (CKAsset, URL) {
        try asset(from: data, name: id.uuidString)
    }

    func asset(from data: Data, name: String) throws -> (CKAsset, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hetpaste-cloudkit-\(name)-\(UUID().uuidString)")
        try data.write(to: url, options: .atomic)
        return (CKAsset(fileURL: url), url)
    }
}

enum CloudKitPersistenceError: LocalizedError {
    case accountUnavailable(CKAccountStatus)
    case invalidRecord(String)
    case assetTooLarge(Int64)
    case missingChunk(Int)
    case corruptChunkPayload

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let status): return "iCloud account is unavailable (status \(status.rawValue))."
        case .invalidRecord(let type): return "An iCloud \(type) record is missing required fields."
        case .assetTooLarge(let bytes): return "This item is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), which exceeds the 50 MB iCloud item limit."
        case .missingChunk(let position): return "Part \(position + 1) of this iCloud item is unavailable."
        case .corruptChunkPayload: return "The downloaded iCloud item failed its integrity check."
        }
    }
}
