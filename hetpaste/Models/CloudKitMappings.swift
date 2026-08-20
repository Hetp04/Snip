import CloudKit
import CryptoKit
import Foundation

enum CloudRecordType {
    static let clipboardItem = "ClipboardItem"
    static let folder = "ClipboardFolder"
    static let chain = "ClipboardChain"
    static let chainItem = "ClipboardChainItem"
    static let wardrobeItem = "WardrobeItem"
    static let clipboardAssetChunk = "ClipboardAssetChunk"
    static let folderMembershipOperation = "FolderMembershipOperation"
}

/// Append-only membership intent. This is the migration path away from
/// overwriting a card's folder set during concurrent edits on different devices.
struct FolderMembershipOperation: Codable, Identifiable {
    enum Kind: String, Codable { case add, remove }
    let id: UUID
    let itemID: UUID
    let folderID: UUID
    let kind: Kind
    let createdAt: Date

    func cloudRecord() -> CKRecord {
        let record = CKRecord(recordType: CloudRecordType.folderMembershipOperation,
                              recordID: CloudKitManager.shared.recordID(type: CloudRecordType.folderMembershipOperation, id: id))
        record["uuid"] = id.uuidString
        record["itemID"] = itemID.uuidString
        record["folderID"] = folderID.uuidString
        record["kind"] = kind.rawValue
        record["createdAt"] = createdAt
        return record
    }
}

extension CKRecord {
    func string(_ key: String) -> String? { self[key] as? String }
    func data(_ key: String) -> Data? { self[key] as? Data }
    func date(_ key: String) -> Date? { self[key] as? Date }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func int64(_ key: String) -> Int64? { (self[key] as? NSNumber)?.int64Value }
    func bool(_ key: String) -> Bool { (self[key] as? NSNumber)?.boolValue ?? false }
    func doubles(_ key: String) -> [Double]? {
        if let data = self[key] as? Data { return CloudKitVectorCodec.decode(data) }
        return self[key] as? [Double]
    }
    func uuids(_ key: String) -> Set<UUID> {
        Set((self[key] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
    }
}

/// Large rich-text payloads cannot live in regular CKRecord fields. They are
/// encoded into the record's existing `asset` field instead, keeping the
/// record metadata queryable and the full content available on other devices.
struct CloudClipboardPayload: Codable {
    static let storagePrefix = "cloud-payload-v2:"
    let version: Int
    let checksum: String
    let contentText: String?
    let previewText: String?
    let rtfData: Data?
    let htmlData: Data?
    let rtfdData: Data?
    let attachmentChecksum: String?

    init(item: ClipboardItem) {
        version = 3
        contentText = item.contentText
        previewText = item.previewText
        rtfData = item.rtfData
        htmlData = item.htmlData
        rtfdData = item.rtfdData
        attachmentChecksum = rtfdData.map(Self.sha256)
        checksum = Self.checksum(contentText: contentText, rtfData: rtfData, htmlData: htmlData, rtfdData: rtfdData)
    }

    private enum CodingKeys: String, CodingKey { case version, checksum, contentText, previewText, rtfData, htmlData, rtfdData, attachmentChecksum }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        contentText = try values.decodeIfPresent(String.self, forKey: .contentText)
        previewText = try values.decodeIfPresent(String.self, forKey: .previewText)
        rtfData = try values.decodeIfPresent(Data.self, forKey: .rtfData)
        htmlData = try values.decodeIfPresent(Data.self, forKey: .htmlData)
        rtfdData = try values.decodeIfPresent(Data.self, forKey: .rtfdData)
        attachmentChecksum = try values.decodeIfPresent(String.self, forKey: .attachmentChecksum)
        checksum = try values.decodeIfPresent(String.self, forKey: .checksum)
            ?? Self.checksum(contentText: contentText, rtfData: rtfData, htmlData: htmlData, rtfdData: rtfdData)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version); try values.encode(checksum, forKey: .checksum)
        try values.encodeIfPresent(contentText, forKey: .contentText); try values.encodeIfPresent(previewText, forKey: .previewText)
        try values.encodeIfPresent(rtfData, forKey: .rtfData); try values.encodeIfPresent(htmlData, forKey: .htmlData); try values.encodeIfPresent(rtfdData, forKey: .rtfdData)
        try values.encodeIfPresent(attachmentChecksum, forKey: .attachmentChecksum)
    }

    static func checksum(contentText: String?, rtfData: Data?, htmlData: Data?, rtfdData: Data?) -> String {
        // Length-prefix every part. The former raw concatenation made
        // different component boundaries ambiguous ("ab" + "c" vs "a" + "bc").
        var data = Data("sniphet-rich-payload-v3".utf8)
        for component in [contentText.map { Data($0.utf8) }, rtfData, htmlData, rtfdData] {
            var length = UInt64(component?.count ?? 0).bigEndian
            data.append(Data(bytes: &length, count: MemoryLayout<UInt64>.size))
            if let component { data.append(component) }
        }
        return sha256(data)
    }

    static func encodedIfRequired(for item: ClipboardItem) throws -> Data? {
        // Binary data and rich HTML can easily exceed CloudKit's practical
        // inline-record budget (about 1 MB). Leave headroom for metadata.
        let textBytes = item.contentText?.utf8.count ?? 0
        let rtfBytes = item.rtfData?.count ?? 0
        let htmlBytes = item.htmlData?.count ?? 0
        let rtfdBytes = item.rtfdData?.count ?? 0
        let inlineBytes = textBytes + rtfBytes + htmlBytes + rtfdBytes
        guard item.localData == nil, inlineBytes > 650 * 1024 else { return nil }
        return try JSONEncoder().encode(CloudClipboardPayload(item: item))
    }

    static func checksum(for item: ClipboardItem) -> String {
        checksum(contentText: item.contentText, rtfData: item.rtfData, htmlData: item.htmlData, rtfdData: item.rtfdData)
    }

    static func decode(from data: Data) -> CloudClipboardPayload? {
        guard let payload = try? JSONDecoder().decode(CloudClipboardPayload.self, from: data),
              (payload.version < 3 || payload.attachmentChecksum == payload.rtfdData.map(sha256)),
              payload.checksum == (payload.version < 3
                ? legacyChecksum(contentText: payload.contentText, rtfData: payload.rtfData, htmlData: payload.htmlData, rtfdData: payload.rtfdData)
                : checksum(contentText: payload.contentText, rtfData: payload.rtfData, htmlData: payload.htmlData, rtfdData: payload.rtfdData))
        else { return nil }
        return payload
    }

    private static func legacyChecksum(contentText: String?, rtfData: Data?, htmlData: Data?, rtfdData: Data?) -> String {
        var data = Data()
        if let contentText { data.append(contentsOf: contentText.utf8) }
        for representation in [rtfData, htmlData, rtfdData] { if let representation { data.append(representation) } }
        return sha256(data)
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Compact manifest stored on the parent ClipboardItem record. Chunk records
/// use deterministic names, so download and cleanup require no CloudKit query
/// or schema index.
struct CloudChunkManifest: Codable, Equatable {
    enum Kind: String, Codable { case binary, richPayload }
    static let storagePrefix = "cloud-chunks-v1"
    let kind: Kind
    let count: Int
    let byteCount: Int64
    let checksum: String

    init?(storagePath: String?) {
        guard let storagePath else { return nil }
        let values = storagePath.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard values.count == 5, values[0] == Self.storagePrefix,
              let kind = Kind(rawValue: values[1]), let count = Int(values[2]),
              let byteCount = Int64(values[3]), count > 0, byteCount >= 0,
              values[4].count == 64,
              values[4].allSatisfy({ $0.isHexDigit }) else { return nil }
        self.kind = kind; self.count = count; self.byteCount = byteCount; self.checksum = values[4]
    }

    init(kind: Kind, data: Data, chunkSize: Int) {
        self.kind = kind
        self.count = max(1, Int(ceil(Double(data.count) / Double(chunkSize))))
        self.byteCount = Int64(data.count)
        self.checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    init(kind: Kind, count: Int, byteCount: Int64, checksum: String) {
        self.kind = kind; self.count = count; self.byteCount = byteCount; self.checksum = checksum
    }

    var storagePath: String { "\(Self.storagePrefix):\(kind.rawValue):\(count):\(byteCount):\(checksum)" }
    func isValid(_ data: Data) -> Bool {
        Int64(data.count) == byteCount && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == checksum
    }
}

extension String {
    func cloudKitInlineValue(maximumUTF8Bytes: Int) -> String {
        guard utf8.count > maximumUTF8Bytes else { return self }
        var end = startIndex
        var bytes = 0
        while end < endIndex {
            let next = index(after: end)
            let size = self[end..<next].utf8.count
            guard bytes + size <= maximumUTF8Bytes else { break }
            bytes += size
            end = next
        }
        return String(self[..<end])
    }
}

extension ClipboardItem {
    func cloudRecord(existing: CKRecord? = nil) -> CKRecord {
        let manager = CloudKitManager.shared
        let record = existing ?? CKRecord(recordType: CloudRecordType.clipboardItem,
                                          recordID: manager.recordID(type: CloudRecordType.clipboardItem, id: id))
        record["uuid"] = id.uuidString
        record["contentType"] = contentType.rawValue
        record["contentText"] = contentText?.cloudKitInlineValue(maximumUTF8Bytes: 512 * 1024)
        record["sourceAppName"] = sourceAppName
        record["sourceBundleID"] = sourceAppBundleID
        record["appIconData"] = appIconData
        // CloudKit cannot infer a list's element type from an empty value when
        // a development schema is first created. Absence represents no folder.
        record["folderIDs"] = folderIDs.isEmpty ? nil : folderIDs.map(\.uuidString)
        record["isPinned"] = isPinned as NSNumber
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt ?? createdAt
        record["syncStatus"] = SyncStatus.synced.rawValue
        record["storagePath"] = storagePath
        record["fileName"] = fileName
        record["fileSize"] = fileSize.map(NSNumber.init(value:))
        record["mimeType"] = mimeType
        record["rtfData"] = rtfData
        record["htmlData"] = htmlData
        record["rtfdData"] = rtfdData
        record["richPayloadChecksum"] = hasPortableRichText ? CloudClipboardPayload.checksum(for: self) : nil
        record["richPayloadVersion"] = hasPortableRichText ? NSNumber(value: 3) : nil
        record["detectedLanguage"] = detectedLanguage
        record["isDeleted"] = isDeleted as NSNumber
        record["deletedAt"] = deletedAt
        record["searchContext"] = searchContext?.cloudKitInlineValue(maximumUTF8Bytes: 192 * 1024)
        record["contextSourceHash"] = contextSourceHash
        // A 3,072-dimensional embedding exceeds CloudKit's practical List
        // limits. Persist it as compact Float32 data instead of a CK list.
        record["rawEmbedding"] = rawEmbedding.map(CloudKitVectorCodec.encode)
        record["embedding"] = embedding.map(CloudKitVectorCodec.encode)
        record["embeddingStatus"] = embeddingStatus
        // A small JPEG preview is safe inline metadata and lets another Mac
        // draw the card without downloading the original multi-megabyte asset.
        record["thumbnailData"] = ThumbnailCache.shared.data(for: id)
        return record
    }

    init(cloudRecord record: CKRecord) throws {
        guard let uuid = record.string("uuid").flatMap(UUID.init(uuidString:)),
              let type = record.string("contentType").flatMap(ContentType.init(rawValue:)),
              let source = record.string("sourceAppName") else {
            throw CloudKitPersistenceError.invalidRecord(CloudRecordType.clipboardItem)
        }
        id = uuid; contentType = type; contentText = record.string("contentText")
        sourceAppName = source; sourceAppBundleID = record.string("sourceBundleID")
        appIconData = record.data("appIconData")
        folderIDs = record.uuids("folderIDs"); isPinned = record.bool("isPinned")
        createdAt = record.date("createdAt") ?? record.creationDate ?? Date()
        updatedAt = record.date("updatedAt") ?? record.modificationDate ?? createdAt
        syncStatus = SyncStatus(rawValue: record.string("syncStatus") ?? "synced") ?? .synced
        storagePath = record.string("storagePath"); fileName = record.string("fileName")
        fileSize = record.int64("fileSize"); mimeType = record.string("mimeType")
        rtfData = record.data("rtfData"); htmlData = record.data("htmlData"); rtfdData = record.data("rtfdData")
        richPayloadChecksum = record.string("richPayloadChecksum")
        richPayloadVersion = record.int("richPayloadVersion")
        detectedLanguage = record.string("detectedLanguage"); isDeleted = record.bool("isDeleted")
        deletedAt = record.date("deletedAt"); searchContext = record.string("searchContext")
        contextSourceHash = record.string("contextSourceHash"); rawEmbedding = record.doubles("rawEmbedding")
        embedding = record.doubles("embedding"); embeddingStatus = record.string("embeddingStatus") ?? "pending"
        localData = nil
        // Legacy records did not carry integrity metadata. New records must
        // match before their inline rich representations are trusted.
        if let richPayloadChecksum, rtfData != nil || htmlData != nil || rtfdData != nil,
           richPayloadChecksum != CloudClipboardPayload.checksum(for: self) {
            rtfData = nil; htmlData = nil; rtfdData = nil
            contentType = .text
        }
        if let thumbnail = record.data("thumbnailData") { ThumbnailCache.shared.store(thumbnail, for: id) }
    }
}

enum CloudKitVectorCodec {
    nonisolated static func encode(_ vector: [Double]) -> Data {
        vector.reduce(into: Data(capacity: vector.count * MemoryLayout<UInt32>.size)) { data, value in
            var bits = Float(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }

    nonisolated static func decode(_ data: Data) -> [Double]? {
        guard data.count.isMultiple(of: MemoryLayout<UInt32>.size) else { return nil }
        return data.withUnsafeBytes { bytes in
            bytes.bindMemory(to: UInt32.self).map { Double(Float(bitPattern: UInt32(littleEndian: $0))) }
        }
    }
}

extension ClipboardFolder {
    func cloudRecord(existing: CKRecord? = nil) -> CKRecord {
        let r = existing ?? CKRecord(recordType: CloudRecordType.folder, recordID: CloudKitManager.shared.recordID(type: CloudRecordType.folder, id: id))
        r["uuid"] = id.uuidString; r["name"] = name; r["createdAt"] = createdAt; r["updatedAt"] = updatedAt
        return r
    }
    init(cloudRecord r: CKRecord) throws {
        guard let id = r.string("uuid").flatMap(UUID.init(uuidString:)), let name = r.string("name") else { throw CloudKitPersistenceError.invalidRecord(CloudRecordType.folder) }
        self.init(id: id, name: name, createdAt: r.date("createdAt") ?? r.creationDate ?? Date(), updatedAt: r.date("updatedAt") ?? r.modificationDate ?? Date())
    }
}

extension WardrobeItem {
    func cloudRecord(existing: CKRecord? = nil) -> CKRecord {
        let r = existing ?? CKRecord(recordType: CloudRecordType.wardrobeItem, recordID: CloudKitManager.shared.recordID(type: CloudRecordType.wardrobeItem, id: id))
        r["uuid"] = id.uuidString; r["contentType"] = contentType.rawValue; r["content"] = content
        r["source"] = source.rawValue; r["sourceSnippetID"] = sourceSnippetID?.uuidString
        r["sourceAppName"] = sourceAppName; r["sourceBundleID"] = sourceAppBundleID
        r["storagePath"] = storagePath; r["fileName"] = fileName; r["fileSize"] = fileSize.map(NSNumber.init(value:))
        r["mimeType"] = mimeType; r["fileExtension"] = fileExtension; r["createdAt"] = createdAt; r["updatedAt"] = updatedAt ?? createdAt
        return r
    }
    init(cloudRecord r: CKRecord) throws {
        guard let id = r.string("uuid").flatMap(UUID.init(uuidString:)), let type = r.string("contentType").flatMap(ContentType.init(rawValue:)) else { throw CloudKitPersistenceError.invalidRecord(CloudRecordType.wardrobeItem) }
        self.init(id: id, userID: nil, contentType: type, content: r.string("content"), source: WardrobeSource(rawValue: r.string("source") ?? "external") ?? .external,
                  sourceSnippetID: r.string("sourceSnippetID").flatMap(UUID.init(uuidString:)), sourceAppName: r.string("sourceAppName"), sourceAppBundleID: r.string("sourceBundleID"),
                  storagePath: r.string("storagePath"), fileName: r.string("fileName"), fileSize: r.int64("fileSize"), mimeType: r.string("mimeType"), fileExtension: r.string("fileExtension"),
                  createdAt: r.date("createdAt") ?? r.creationDate ?? Date(), updatedAt: r.date("updatedAt") ?? r.modificationDate, localData: nil, originalFilePath: nil)
    }
}

extension Chain {
    init(cloudRecord record: CKRecord) throws {
        guard let id = record.string("uuid").flatMap(UUID.init(uuidString:)),
              let name = record.string("name") else {
            throw CloudKitPersistenceError.invalidRecord(CloudRecordType.chain)
        }
        self.init(
            id: id,
            name: name,
            createdAt: record.date("createdAt") ?? record.creationDate ?? Date(),
            updatedAt: record.date("updatedAt") ?? record.modificationDate ?? Date()
        )
    }
}

extension ChainItem {
    init(cloudRecord record: CKRecord) throws {
        guard let id = record.string("uuid").flatMap(UUID.init(uuidString:)),
              let chainID = record.string("chainID").flatMap(UUID.init(uuidString:)),
              let snippetID = record.string("snippetID").flatMap(UUID.init(uuidString:)) else {
            throw CloudKitPersistenceError.invalidRecord(CloudRecordType.chainItem)
        }
        self.init(id: id, chainID: chainID, snippetID: snippetID, position: record.int("position") ?? 0)
    }
}
