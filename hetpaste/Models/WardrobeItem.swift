import Foundation

enum WardrobeSource: String, Codable {
    case external = "external"
    case internalReference = "internal_reference"
}

struct WardrobeItem: Identifiable, Codable {
    var id: UUID = UUID()
    var userID: UUID?
    var contentType: ContentType
    var content: String?
    var source: WardrobeSource
    var sourceSnippetID: UUID?
    var sourceAppName: String?
    var sourceAppBundleID: String?
    var storagePath: String?
    var fileName: String?
    var fileSize: Int64?
    var mimeType: String?
    var fileExtension: String?  // Store extension for icon lookup
    var createdAt: Date = Date()
    
    // Local data for files/images before upload
    var localData: Data?
    
    // Transient: original file path (not persisted, for icon lookup)
    var originalFilePath: String?
    
    var previewText: String? {
        guard let text = content else { return fileName }
        return String(text.prefix(280))
    }
    
    var bucket: String? {
        switch contentType {
        case .image, .video, .file:
            return "wardrobe-items"
        case .text, .richText, .url:
            return nil
        }
    }
}

// MARK: - Supabase Record

struct WardrobeRecord: Codable {
    let id: String
    let user_id: String?
    let content_type: String
    let content: String?
    let source: String
    let source_snippet_id: String?
    let source_app_name: String?
    let source_bundle_id: String?
    let storage_path: String?
    let file_name: String?
    let file_size: Int64?
    let mime_type: String?
    let file_extension: String?
    let created_at: String?
}

extension WardrobeItem {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    func toRecord() -> WardrobeRecord {
        WardrobeRecord(
            id: id.uuidString,
            user_id: userID?.uuidString,
            content_type: contentType.rawValue,
            content: content,
            source: source.rawValue,
            source_snippet_id: sourceSnippetID?.uuidString,
            source_app_name: sourceAppName,
            source_bundle_id: sourceAppBundleID,
            storage_path: storagePath,
            file_name: fileName,
            file_size: fileSize,
            mime_type: mimeType,
            file_extension: fileExtension,
            created_at: Self.isoFormatter.string(from: createdAt)
        )
    }
    
    init(record: WardrobeRecord) {
        self.id = UUID(uuidString: record.id) ?? UUID()
        self.userID = record.user_id.flatMap(UUID.init(uuidString:))
        self.contentType = ContentType(rawValue: record.content_type) ?? .text
        self.content = record.content
        self.source = WardrobeSource(rawValue: record.source) ?? .external
        self.sourceSnippetID = record.source_snippet_id.flatMap(UUID.init(uuidString:))
        self.sourceAppName = record.source_app_name
        self.sourceAppBundleID = record.source_bundle_id
        self.storagePath = record.storage_path
        self.fileName = record.file_name
        self.fileSize = record.file_size
        self.mimeType = record.mime_type
        self.fileExtension = record.file_extension
        
        if let created = record.created_at {
            self.createdAt = WardrobeItem.isoFormatter.date(from: created)
                ?? WardrobeItem.isoFormatterNoFraction.date(from: created)
                ?? Date()
        } else {
            self.createdAt = Date()
        }
        
        self.localData = nil
        self.originalFilePath = nil
    }
}
