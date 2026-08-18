import CloudKit
import Foundation

struct CloudBatchDeletionFailure: Error {
    let deletedRecordIDs: Set<CKRecord.ID>
    let underlyingError: Error
}

private enum CloudBatchDeletionInternalError: Error {
    case missingResult
}

/// The single entry point for the user's private iCloud clipboard library.
/// Stable UUIDs are used as CloudKit record names so models never depend on
/// temporary CKRecord instances. CloudKit's server-record-changed error is
/// resolved last-writer-wins using each model's updated timestamp.
final class CloudKitManager {
    static let shared = CloudKitManager()

    let container: CKContainer
    let database: CKDatabase
    let libraryZoneID = CKRecordZone.ID(zoneName: "ClipboardLibrary")
    private var isPrepared = false
    private var preparationTask: Task<Void, Error>?

    private init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func verifyAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw CloudKitPersistenceError.accountUnavailable(status) }
        try await prepareLibraryZone()
    }

    func record(type: String, id: UUID) async throws -> CKRecord? {
        try await record(type: type, recordName: "\(type).\(id.uuidString.lowercased())")
    }

    func record(type: String, recordName: String) async throws -> CKRecord? {
        try await verifyAccount()
        do { return try await database.record(for: recordID(type: type, recordName: recordName)) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    @discardableResult
    func save(_ record: CKRecord) async throws -> CKRecord {
        try await verifyAccount()
        do { return try await database.save(record) }
        catch let error as CKError where error.code == .serverRecordChanged {
            guard let server = error.serverRecord else { throw error }
            // Deterministic conflict rule: last modification wins. A queued
            // offline change retains its original updatedAt, so it cannot
            // overwrite a newer edit made on another device.
            let localUpdatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? .distantPast
            let serverUpdatedAt = server["updatedAt"] as? Date ?? server.modificationDate ?? .distantPast
            guard localUpdatedAt > serverUpdatedAt else { return server }
            let temporaryAssetURLs = try copyFields(from: record, to: server)
            defer { removeTemporaryAssets(at: temporaryAssetURLs) }
            return try await database.save(server)
        }
    }

    func delete(type: String, id: UUID) async throws {
        try await delete(type: type, recordName: "\(type).\(id.uuidString.lowercased())")
    }

    func delete(type: String, recordName: String) async throws {
        try await verifyAccount()
        do { _ = try await database.deleteRecord(withID: recordID(type: type, recordName: recordName)) }
        catch let error as CKError where error.code == .unknownItem { return }
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
        // Do not send sort descriptors until the first record has defined the
        // corresponding field in a new development schema. This lets a clean
        // CloudKit container bootstrap itself instead of failing before its
        // first save; callers retain their requested order locally.
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

    /// Retrieves the first, server-sorted metadata page for a new local index.
    /// This lets the UI show recent cards before historical import completes.
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
                _ = try await database.deleteRecord(withID: id)
            }
            cursor = page.queryCursor
        } while cursor != nil
    }

    /// Deletes query matches in bounded, non-atomic batches. Successful record
    /// IDs are retained when CloudKit reports a partial failure so callers can
    /// update only the local rows that are known to be gone from iCloud.
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

                for start in stride(from: 0, to: recordIDs.count, by: batchSize) {
                    let end = min(start + batchSize, recordIDs.count)
                    let batch = Array(recordIDs[start..<end])
                    let result = try await database.modifyRecords(
                        saving: [],
                        deleting: batch,
                        savePolicy: .ifServerRecordUnchanged,
                        atomically: false
                    )
                    var firstFailure: Error?
                    for id in batch {
                        switch result.deleteResults[id] {
                        case .success?:
                            deleted.insert(id)
                        case let .failure(error)?:
                            if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                                deleted.insert(id)
                            } else if firstFailure == nil {
                                firstFailure = error
                            }
                        case nil:
                            if firstFailure == nil {
                                firstFailure = CloudBatchDeletionInternalError.missingResult
                            }
                        }
                    }
                    progress?(deleted.count)
                    if let firstFailure {
                        throw CloudBatchDeletionFailure(deletedRecordIDs: deleted, underlyingError: firstFailure)
                    }
                }
                cursor = page.queryCursor
            } while cursor != nil
            return deleted
        } catch let partial as CloudBatchDeletionFailure {
            throw partial
        } catch {
            if deleted.isEmpty { throw error }
            throw CloudBatchDeletionFailure(deletedRecordIDs: deleted, underlyingError: error)
        }
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

    /// Advances the persisted server-change token for the custom zone. The
    /// caller can refresh its model only when another device changed records.
    func consumeRemoteChanges(
        onRecordsChanged: @escaping ([CKRecord]) -> Void = { _ in },
        onRecordsDeleted: @escaping ([CKRecord.ID]) -> Void = { _ in },
        onPageApplied: @escaping () -> Void = {}
    ) async throws -> Bool {
        try await verifyAccount()
        let key = "cloudkit.library-zone-change-token"
        let savedToken = UserDefaults.standard.data(forKey: key).flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        var token = savedToken
        var changed = false
        while true {
            do {
                let fetchedPage = try await database.recordZoneChanges(inZoneWith: libraryZoneID, since: token)
                var modifications: [CKRecord] = []
                for (_, result) in fetchedPage.modificationResultsByID {
                    modifications.append(try result.get().record)
                }
                let deletions = fetchedPage.deletions.map(\.recordID)
                if !modifications.isEmpty { onRecordsChanged(modifications) }
                if !deletions.isEmpty { onRecordsDeleted(deletions) }
                changed = changed || !modifications.isEmpty || !deletions.isEmpty
                if !modifications.isEmpty || !deletions.isEmpty { onPageApplied() }
                token = fetchedPage.changeToken
                if !fetchedPage.moreComing { break }
            } catch let error as CKError where error.code == .changeTokenExpired {
                UserDefaults.standard.removeObject(forKey: key)
                token = nil
                continue
            }
        }
        if let token, let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return changed
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

    /// CKAsset instances belong to one CKRecord only. When a legacy record is
    /// copied into the custom zone (or a conflict is retried), make a new asset
    /// backed by a separate temporary file rather than assigning the existing
    /// CKAsset instance to another record.
    @discardableResult
    private func copyFields(from source: CKRecord, to destination: CKRecord) throws -> [URL] {
        var temporaryAssetURLs: [URL] = []
        do {
            for key in source.allKeys() {
                guard let asset = source[key] as? CKAsset else {
                    destination[key] = source[key]
                    continue
                }

                guard let sourceURL = asset.fileURL else {
                    // An unavailable asset cannot be copied safely. Leaving the
                    // destination field empty is preferable to crashing or
                    // corrupting the whole migration.
                    destination[key] = nil
                    continue
                }

                let copiedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("hetpaste-cloudkit-copy-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: sourceURL, to: copiedURL)
                destination[key] = CKAsset(fileURL: copiedURL)
                temporaryAssetURLs.append(copiedURL)
            }
            return temporaryAssetURLs
        } catch {
            removeTemporaryAssets(at: temporaryAssetURLs)
            throw error
        }
    }

    private func removeTemporaryAssets(at urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private func prepareLibraryZone() async throws {
        guard !isPrepared else { return }
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let task = Task { [unowned self] in
            do { _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: libraryZoneID)], deleting: []) }
            catch let error as CKError where error.code == .serverRejectedRequest { /* zone already exists */ }
            try await installSubscription()
        }
        preparationTask = task
        defer { preparationTask = nil }
        try await task.value
        isPrepared = true
    }



    private func installSubscription() async throws {
        let id = "clipboard-library-zone-changes"
        let subscription = CKRecordZoneSubscription(zoneID: libraryZoneID, subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do { _ = try await database.modifySubscriptions(saving: [subscription], deleting: []) }
        catch let error as CKError where error.code == .serverRejectedRequest || error.code == .unknownItem { return }
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
