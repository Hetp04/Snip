import CloudKit
import Foundation

struct SemanticSearchHit: Sendable { let id: UUID; let similarity: Double }

struct ClipboardHistoryDeletionFailure: Error {
    let deletedItemIDs: Set<UUID>
    let underlyingError: Error
}

final class ClipboardRepository {
    private let cloud = CloudKitManager.shared
    /// Deliberately below CloudKit's per-record asset ceiling. Large captures
    /// are represented by a tiny manifest on the parent record plus these
    /// independent assets, so capture itself has no product-imposed size cap.
    private static let chunkSize = 16 * 1024 * 1024

    func fetchAll() async throws -> [ClipboardItem] {
        try await cloud.verifyAccount()
        return try await cloud.fetchAll(type: CloudRecordType.clipboardItem, sort: [NSSortDescriptor(key: "createdAt", ascending: false)]).compactMap { try? ClipboardItem(cloudRecord: $0) }
    }
    func fetchRecent(limit: Int) async throws -> [ClipboardItem] {
        try await cloud.fetchFirstPage(
            type: CloudRecordType.clipboardItem,
            sort: NSSortDescriptor(key: "createdAt", ascending: false),
            limit: limit
        ).compactMap { try? ClipboardItem(cloudRecord: $0) }
    }
    func save(_ item: ClipboardItem) async throws -> ClipboardItem {
        var synced = item
        synced.syncStatus = .synced
        let existing = try await cloud.record(type: CloudRecordType.clipboardItem, id: item.id)
        let oldManifest = CloudChunkManifest(storagePath: existing?.string("storagePath"))
        let record = synced.cloudRecord(existing: existing)
        var temp: URL?
        // Metadata-only writes (pin, folder, sync state) must retain an
        // already-uploaded chunk set; they do not carry the binary payload.
        var newManifest: CloudChunkManifest? = oldManifest
        var uploadedChunkCount = 0
        var savedRecord: CKRecord?
        let payload = try CloudClipboardPayload.encodedIfRequired(for: item)

        do {
            if let payload {
                if payload.count <= Self.chunkSize * 3 {
                    newManifest = nil
                    let pair = try cloud.asset(from: payload, id: item.id)
                    record["asset"] = pair.0
                    record["contentText"] = nil
                    record["rtfData"] = nil
                    record["htmlData"] = nil
                    record["rtfdData"] = nil
                    synced.storagePath = "\(CloudClipboardPayload.storagePrefix)\(item.id.uuidString)"
                    record["storagePath"] = synced.storagePath
                    temp = pair.1
                } else {
                    let manifest = try await uploadChunks(payload, parentID: item.id, kind: .richPayload)
                    uploadedChunkCount = manifest.count
                    newManifest = manifest
                    // Keep a bounded text preview in the metadata record so a
                    // fresh device can render the card without downloading a
                    // potentially huge formatted payload.
                    record["asset"] = nil
                    record["contentText"] = item.contentText?.cloudKitInlineValue(maximumUTF8Bytes: 512 * 1024)
                    record["rtfData"] = nil
                    record["htmlData"] = nil
                    record["rtfdData"] = nil
                    synced.storagePath = manifest.storagePath
                    record["storagePath"] = manifest.storagePath
                }
            } else if let data = item.localData {
                if data.count <= Self.chunkSize * 3 {
                    newManifest = nil
                    let pair = try cloud.asset(from: data, id: item.id)
                    record["asset"] = pair.0
                    temp = pair.1
                    synced.storagePath = item.id.uuidString
                    record["storagePath"] = synced.storagePath
                } else {
                    let manifest = try await uploadChunks(data, parentID: item.id, kind: .binary)
                    uploadedChunkCount = manifest.count
                    newManifest = manifest
                    record["asset"] = nil
                    synced.storagePath = manifest.storagePath
                    record["storagePath"] = manifest.storagePath
                }
            }
            defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
            savedRecord = try await cloud.save(record)
        } catch {
            // Keep completed chunks and their durable progress state. A quit,
            // network loss, or retry-after response can resume exactly where
            // it stopped after relaunch instead of re-uploading the file.
            if uploadedChunkCount > 0 { CloudSyncDiagnostics.shared.failLargeTransfer() }
            throw error
        }

        let committedManifest = CloudChunkManifest(storagePath: savedRecord?.string("storagePath"))
        // A server-wins conflict leaves this attempt's version unreachable;
        // discard it without touching the version referenced by the server.
        if let newManifest, newManifest != committedManifest {
            try? await deleteChunks(parentID: item.id, manifest: newManifest, count: newManifest.count)
            CloudChunkTransferStore.shared.discard(itemID: item.id)
            CloudSyncDiagnostics.shared.finishLargeTransfer()
        }
        // Re-saving a card with fewer/no chunks must not retain obsolete
        // assets. The parent is saved first, making the operation recoverable
        // if cleanup is interrupted.
        if let oldManifest, oldManifest != committedManifest {
            try? await deleteChunks(parentID: item.id, manifest: oldManifest, count: oldManifest.count)
        }
        if newManifest == committedManifest {
            CloudChunkTransferStore.shared.complete(itemID: item.id)
            CloudSyncDiagnostics.shared.finishLargeTransfer()
        }
        let didCommitLocal = savedRecord?.date("updatedAt") == record.date("updatedAt")
            && savedRecord?.string("storagePath") == record.string("storagePath")
        if didCommitLocal { return synced }
        return (try? savedRecord.map(ClipboardItem.init(cloudRecord:))) ?? synced
    }
    func updateEmbeddings(id: UUID, rawVector: [Double]?, memoryVector: [Double]?, status: String) async throws { try await mutate(id) { $0["rawEmbedding"] = rawVector.map(CloudKitVectorCodec.encode); $0["embedding"] = memoryVector.map(CloudKitVectorCodec.encode); $0["embeddingStatus"] = status } }
    func updateEmbeddingStatus(id: UUID, status: String) async throws { try await mutate(id) { $0["embeddingStatus"] = status } }
    

    /// Backfill the compact image preview without replacing/re-uploading the
    /// original asset. This makes migrated cards fast on the user's other Macs.
    func updateThumbnail(id: UUID, data: Data) async throws {
        guard let record = try await cloud.record(type: CloudRecordType.clipboardItem, id: id) else { return }
        record["thumbnailData"] = data
        _ = try await cloud.save(record)
    }
    func updateSearchContext(id: UUID, context: String, sourceHash: String) async throws { try await mutate(id) { $0["searchContext"] = context; $0["contextSourceHash"] = sourceHash } }
    func cachedSearchContext(sourceHash: String) async throws -> String? {
        // Keep this lookup local. It avoids a schema/index dependency during a
        // new container's first save and is fast for the bounded library UI.
        return try await fetchAll().first { $0.contextSourceHash == sourceHash }?.searchContext
    }
    func fetchItemsNeedingEmbeddings() async throws -> [ClipboardItem] { try await fetchAll().filter { $0.embeddingStatus == "pending" } }
    func hybridSearch(vector: [Double], rawQuery: String, limit: Int = 40) async throws -> [SemanticSearchHit] {
        let terms = rawQuery.lowercased().split(whereSeparator: \Character.isWhitespace).map(String.init)
        return try await fetchAll().compactMap { item in
            guard let stored = item.embedding ?? item.rawEmbedding else { return nil }
            let text = item.rawSearchableText.lowercased(), boost = terms.isEmpty ? 0 : Double(terms.filter(text.contains).count) / Double(terms.count) * 0.15
            return SemanticSearchHit(id: item.id, similarity: min(1, cosine(vector, stored) + boost))
        }.sorted { $0.similarity > $1.similarity }.prefix(limit).map { $0 }
    }
    func setFavorite(id: UUID, isFavorite: Bool) async throws { try await mutate(id) { $0["isPinned"] = isFavorite as NSNumber } }
    func setDeleted(id: UUID, isDeleted: Bool, deletedAt: Date?) async throws { try await mutate(id) { $0["isDeleted"] = isDeleted as NSNumber; $0["deletedAt"] = deletedAt } }
    func addToFolder(ids: [UUID], folderID: UUID) async throws { for id in Set(ids) { try await mutate(id) { $0["folderIDs"] = [folderID.uuidString] } } }
    func removeFromFolder(id: UUID, folderID: UUID) async throws { try await mutate(id) { var values = $0.uuids("folderIDs"); values.remove(folderID); $0["folderIDs"] = values.isEmpty ? nil : values.map(\.uuidString) } }
    func delete(id: UUID) async throws {
        let manifest = CloudChunkManifest(storagePath: try await cloud.record(type: CloudRecordType.clipboardItem, id: id)?.string("storagePath"))
        try await cloud.delete(type: CloudRecordType.clipboardItem, id: id)
        if let manifest { try? await deleteChunks(parentID: id, manifest: manifest, count: manifest.count) }
    }
    func deleteHistory(
        in range: ClipboardHistoryRange,
        progress: (@Sendable (_ deleted: Int) -> Void)? = nil
    ) async throws -> Set<UUID> {
        let bounds = range.bounds()
        let predicate: NSPredicate
        switch (bounds.start, bounds.end) {
        case let (start?, end?):
            predicate = NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", start as NSDate, end as NSDate)
        case let (start?, nil):
            predicate = NSPredicate(format: "createdAt >= %@", start as NSDate)
        case let (nil, end?):
            predicate = NSPredicate(format: "createdAt <= %@", end as NSDate)
        case (nil, nil):
            predicate = NSPredicate(value: true)
        }

        // Read manifests before deleting parents so their deterministic chunk
        // IDs remain available for cleanup without requiring an index/query.
        let query = CKQuery(recordType: CloudRecordType.clipboardItem, predicate: predicate)
        let manifests = try await cloud.records(matching: query).reduce(into: [UUID: CloudChunkManifest]()) { result, pair in
            guard let record = try? pair.1.get(),
                  let id = Self.itemID(from: record.recordID),
                  let manifest = CloudChunkManifest(storagePath: record.string("storagePath")) else { return }
            result[id] = manifest
        }
        do {
            let recordIDs = try await cloud.deleteMatchingRecords(
                type: CloudRecordType.clipboardItem,
                predicate: predicate,
                progress: progress
            )
            let deleted = Set(recordIDs.compactMap { Self.itemID(from: $0) })
            for id in deleted {
                if let manifest = manifests[id] { try? await deleteChunks(parentID: id, manifest: manifest, count: manifest.count) }
            }
            return deleted
        } catch let partial as CloudBatchDeletionFailure {
            throw ClipboardHistoryDeletionFailure(
                deletedItemIDs: Set(partial.deletedRecordIDs.compactMap { Self.itemID(from: $0) }),
                underlyingError: partial.underlyingError
            )
        }
    }
    func downloadData(for item: ClipboardItem) async throws -> Data? {
        if let manifest = CloudChunkManifest(storagePath: item.storagePath) {
            guard manifest.kind == .binary else { return nil }
            return try await downloadChunks(parentID: item.id, manifest: manifest)
        }
        guard let r = try await cloud.record(type: CloudRecordType.clipboardItem, id: item.id),
              let url = (r["asset"] as? CKAsset)?.fileURL else { return nil }
        return try Data(contentsOf: url)
    }

    func hydrateRichPayload(for item: ClipboardItem) async throws -> ClipboardItem? {
        guard let manifest = CloudChunkManifest(storagePath: item.storagePath), manifest.kind == .richPayload,
              let payload = CloudClipboardPayload.decode(from: try await downloadChunks(parentID: item.id, manifest: manifest)) else { return nil }
        var hydrated = item
        hydrated.contentText = payload.contentText
        hydrated.rtfData = payload.rtfData
        hydrated.htmlData = payload.htmlData
        hydrated.rtfdData = payload.rtfdData
        return hydrated
    }

    /// Removes remote chunks from transfers that cannot resume because their
    /// local source is gone. Active transfers with a disk source are retained
    /// across app launches and resume through the normal pending-item queue.
    func cleanupAbandonedChunkTransfers() async {
        for state in CloudChunkTransferStore.shared.allStates() {
            let parent = try? await cloud.record(type: CloudRecordType.clipboardItem, id: state.itemID)
            let committed = CloudChunkManifest(storagePath: parent?.string("storagePath"))
            if committed == state.manifest {
                // The app quit after committing the parent but before removing
                // the local progress file. It is no longer an active upload.
                CloudChunkTransferStore.shared.complete(itemID: state.itemID)
                continue
            }
            guard !AssetCache.shared.contains(state.itemID) else { continue }
            try? await deleteChunks(parentID: state.itemID, manifest: state.manifest, count: state.manifest.count)
            CloudChunkTransferStore.shared.discard(itemID: state.itemID)
        }
    }

    func fetchFolders() async throws -> [ClipboardFolder] { try await cloud.fetchAll(type: CloudRecordType.folder, sort: [NSSortDescriptor(key: "createdAt", ascending: true)]).compactMap { try? ClipboardFolder(cloudRecord: $0) } }
    func createFolder(id: UUID, name: String, createdAt: Date = Date(), updatedAt: Date = Date()) async throws { _ = try await cloud.save(ClipboardFolder(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt).cloudRecord()) }
    func renameFolder(id: UUID, name: String) async throws { guard let r = try await cloud.record(type: CloudRecordType.folder, id: id) else { return }; r["name"] = name; r["updatedAt"] = Date(); _ = try await cloud.save(r) }
    func deleteFolder(id: UUID) async throws { for item in try await fetchAll().filter({ $0.folderIDs.contains(id) }) { try await removeFromFolder(id: item.id, folderID: id) }; try await cloud.delete(type: CloudRecordType.folder, id: id) }

    func fetchChains() async throws -> [Chain] { try await cloud.fetchAll(type: CloudRecordType.chain, sort: [NSSortDescriptor(key: "createdAt", ascending: true)]).compactMap { r in guard let id = r.string("uuid").flatMap(UUID.init(uuidString:)), let name = r.string("name") else { return nil }; return Chain(id: id, name: name, createdAt: r.date("createdAt") ?? Date(), updatedAt: r.date("updatedAt") ?? Date()) } }
    func fetchChainItems(chainID: UUID) async throws -> [ChainItem] {
        let q = CKQuery(recordType: CloudRecordType.chainItem, predicate: NSPredicate(format: "chainID == %@", chainID.uuidString)); q.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        let records = try await cloud.records(matching: q)
        return records.compactMap { try? $0.1.get() }.compactMap { r in guard let id = r.string("uuid").flatMap(UUID.init(uuidString:)), let snippet = r.string("snippetID").flatMap(UUID.init(uuidString:)) else { return nil }; return ChainItem(id: id, chainID: chainID, snippetID: snippet, position: r.int("position") ?? 0) }
    }
    func createChain(id: UUID, name: String, createdAt: Date = Date(), updatedAt: Date = Date()) async throws { let r = CKRecord(recordType: CloudRecordType.chain, recordID: cloud.recordID(type: CloudRecordType.chain, id: id)); r["uuid"] = id.uuidString; r["name"] = name; r["createdAt"] = createdAt; r["updatedAt"] = updatedAt; _ = try await cloud.save(r) }
    func addChainItems(_ items: [ChainItem], chainID: UUID) async throws { for item in items { let r = CKRecord(recordType: CloudRecordType.chainItem, recordID: cloud.recordID(type: CloudRecordType.chainItem, id: item.id)); r["uuid"] = item.id.uuidString; r["chainID"] = chainID.uuidString; r["snippetID"] = item.snippetID.uuidString; r["position"] = item.position as NSNumber; r["createdAt"] = Date(); _ = try await cloud.save(r) } }
    func renameChain(id: UUID, name: String) async throws { guard let r = try await cloud.record(type: CloudRecordType.chain, id: id) else { return }; r["name"] = name; r["updatedAt"] = Date(); _ = try await cloud.save(r) }
    func deleteChainItems(chainID: UUID) async throws { try await cloud.deleteAll(type: CloudRecordType.chainItem, matching: NSPredicate(format: "chainID == %@", chainID.uuidString)) }
    func deleteChain(id: UUID) async throws { try await deleteChainItems(chainID: id); try await cloud.delete(type: CloudRecordType.chain, id: id) }

    private func mutate(_ id: UUID, _ body: (CKRecord) -> Void) async throws { guard let r = try await cloud.record(type: CloudRecordType.clipboardItem, id: id) else { return }; body(r); r["updatedAt"] = Date(); _ = try await cloud.save(r) }
    private func uploadChunks(_ data: Data, parentID: UUID, kind: CloudChunkManifest.Kind) async throws -> CloudChunkManifest {
        await LargeTransferScheduler.shared.acquire()
        defer { Task { await LargeTransferScheduler.shared.release() } }
        let manifest = CloudChunkManifest(kind: kind, data: data, chunkSize: Self.chunkSize)
        let state = CloudChunkTransferStore.shared.begin(itemID: parentID, manifest: manifest)
        let completedBytes = state.completedIndexes.reduce(Int64(0)) { total, index in
            let lower = index * Self.chunkSize
            let upper = min(lower + Self.chunkSize, data.count)
            return total + Int64(max(0, upper - lower))
        }
        CloudSyncDiagnostics.shared.beginLargeTransfer(totalBytes: manifest.byteCount, completedBytes: completedBytes)
        do {
            for index in 0..<manifest.count {
                if state.completedIndexes.contains(index) { continue }
                let lower = index * Self.chunkSize
                let upper = min(lower + Self.chunkSize, data.count)
                let chunk = data.subdata(in: lower..<upper)
                let name = Self.chunkRecordName(parentID: parentID, manifest: manifest, index: index)
                let pair = try cloud.asset(from: chunk, name: name)
                defer { try? FileManager.default.removeItem(at: pair.1) }
                let record = CKRecord(recordType: CloudRecordType.clipboardAssetChunk,
                                      recordID: cloud.recordID(type: CloudRecordType.clipboardAssetChunk, recordName: name))
                record["parentID"] = parentID.uuidString
                record["position"] = index as NSNumber
                record["byteCount"] = chunk.count as NSNumber
                record["createdAt"] = Date()
                record["asset"] = pair.0
                _ = try await cloud.save(record)
                CloudChunkTransferStore.shared.markCompleted(itemID: parentID, index: index)
                CloudSyncDiagnostics.shared.advanceLargeTransfer(by: Int64(chunk.count))
                // Cooperate with the UI and normal CloudKit work between chunks.
                await Task.yield()
            }
        } catch {
            CloudSyncDiagnostics.shared.failLargeTransfer()
            throw error
        }
        return manifest
    }

    private func downloadChunks(parentID: UUID, manifest: CloudChunkManifest) async throws -> Data {
        await LargeTransferScheduler.shared.acquire()
        defer { Task { await LargeTransferScheduler.shared.release() } }
        var data = Data()
        data.reserveCapacity(Int(manifest.byteCount))
        CloudSyncDiagnostics.shared.beginLargeTransfer(totalBytes: manifest.byteCount)
        do {
            for index in 0..<manifest.count {
                let name = Self.chunkRecordName(parentID: parentID, manifest: manifest, index: index)
                guard let record = try await cloud.record(type: CloudRecordType.clipboardAssetChunk, recordName: name),
                      let url = (record["asset"] as? CKAsset)?.fileURL else { throw CloudKitPersistenceError.missingChunk(index) }
                let chunk = try Data(contentsOf: url)
                data.append(chunk)
                CloudSyncDiagnostics.shared.advanceLargeTransfer(by: Int64(chunk.count))
                await Task.yield()
            }
        } catch {
            CloudSyncDiagnostics.shared.failLargeTransfer()
            throw error
        }
        guard manifest.isValid(data) else {
            CloudSyncDiagnostics.shared.failLargeTransfer()
            throw CloudKitPersistenceError.corruptChunkPayload
        }
        CloudSyncDiagnostics.shared.finishLargeTransfer()
        return data
    }

    private func deleteChunks(parentID: UUID, manifest: CloudChunkManifest, count: Int) async throws {
        try await deleteChunks(parentID: parentID, manifest: manifest, from: 0, to: count)
    }

    private func deleteChunks(parentID: UUID, manifest: CloudChunkManifest, from: Int, to: Int) async throws {
        guard from < to else { return }
        for index in from..<to {
            try await cloud.delete(type: CloudRecordType.clipboardAssetChunk,
                                   recordName: Self.chunkRecordName(parentID: parentID, manifest: manifest, index: index))
        }
    }

    private static func chunkRecordName(parentID: UUID, manifest: CloudChunkManifest, index: Int) -> String {
        // Checksum namespaces a version of the content. A failed replacement
        // therefore cannot damage the chunk set still referenced by the parent.
        "\(CloudRecordType.clipboardAssetChunk).\(parentID.uuidString.lowercased()).\(manifest.checksum).\(String(format: "%08d", index))"
    }
    private static func itemID(from recordID: CKRecord.ID) -> UUID? {
        let components = recordID.recordName.split(separator: ".", maxSplits: 1)
        guard components.count == 2, components[0] == Substring(CloudRecordType.clipboardItem) else { return nil }
        return UUID(uuidString: String(components[1]))
    }
    private func cosine(_ a: [Double], _ b: [Double]) -> Double { guard a.count == b.count, !a.isEmpty else { return 0 }; let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }, x = sqrt(a.reduce(0) { $0 + $1 * $1 }), y = sqrt(b.reduce(0) { $0 + $1 * $1 }); return x > 0 && y > 0 ? dot / (x * y) : 0 }
}
