import Foundation
enum SyncStatus: String, Codable {
    case pending   
    case synced    
    case failed    
}
struct ClipboardItem: Identifiable {
    var id: UUID = UUID()
    var contentType: ContentType
    var contentText: String?            
    var sourceAppName: String
    var sourceAppBundleID: String?
    var folderID: UUID? = nil
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var syncStatus: SyncStatus = .synced
    var storagePath: String?            
    var fileName: String?
    var fileSize: Int64?
    var mimeType: String?
    var originalFileURL: URL? = nil
    var rtfData: Data? = nil
    var htmlData: Data? = nil
    var rtfdData: Data? = nil
    var localData: Data?
    var rawPasteboardData: [String: Data]? = nil
    var queuePosition: Int? = nil
    var queuedAt: Date? = nil
    var isQueueHead: Bool { queuePosition == 0 }
    var detectedLanguage: String? = nil
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    func queuePreviewText() -> String {
        return previewText ?? fileName ?? "Unknown item"
    }
    var previewText: String? {
        guard let text = contentText else { return fileName }
        return String(text.prefix(280))
    }
    var bucket: String? {
        switch contentType {
        case .image: return AppConstants.Bucket.images
        case .video: return AppConstants.Bucket.videos
        case .file:  return AppConstants.Bucket.files
        case .text, .richText, .url: return nil
        }
    }
}
struct ClipboardRecord: Codable {
    let id: String
    let type: String
    let title: String?
    let preview_text: String?
    let full_text: String?
    let source_app_name: String
    let source_bundle_id: String?
    let folder_id: String?
    let created_at: String?
    let is_favorite: Bool
    let storage_path: String?
    let file_name: String?
    let file_size: Int64?
    let mime_type: String?
    let sync_status: String?
    let detected_language: String?
    let rtf_data: String?
    let html_data: String?
    let rtfd_data: String?
}
extension ClipboardItem {
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
    func toRecord() -> ClipboardRecord {
        ClipboardRecord(
            id: id.uuidString,
            type: contentType.rawValue,
            title: sourceAppName,
            preview_text: previewText,
            full_text: contentText,
            source_app_name: sourceAppName,
            source_bundle_id: sourceAppBundleID,
            folder_id: folderID?.uuidString,
            created_at: Self.isoFormatter.string(from: createdAt),
            is_favorite: isPinned,
            storage_path: storagePath,
            file_name: fileName,
            file_size: fileSize,
            mime_type: mimeType,
            sync_status: SyncStatus.synced.rawValue,
            detected_language: detectedLanguage,
            rtf_data: rtfData?.base64EncodedString(),
            html_data: htmlData?.base64EncodedString(),
            rtfd_data: rtfdData?.base64EncodedString()
        )
    }
    init(record: ClipboardRecord) {
        self.id = UUID(uuidString: record.id) ?? UUID()
        self.contentType = ContentType(rawValue: record.type) ?? .text
        self.contentText = record.full_text ?? record.preview_text
        self.sourceAppName = record.source_app_name
        self.sourceAppBundleID = record.source_bundle_id
        self.folderID = record.folder_id.flatMap(UUID.init(uuidString:))
        self.isPinned = record.is_favorite
        if let created = record.created_at {
            self.createdAt = ClipboardItem.isoFormatter.date(from: created)
                ?? ClipboardItem.isoFormatterNoFraction.date(from: created)
                ?? Date()
        } else {
            self.createdAt = Date()
        }
        self.syncStatus = SyncStatus(rawValue: record.sync_status ?? "synced") ?? .synced
        self.storagePath = record.storage_path
        self.fileName = record.file_name
        self.fileSize = record.file_size
        self.mimeType = record.mime_type
        self.detectedLanguage = record.detected_language
        self.rtfData = record.rtf_data.flatMap { Data(base64Encoded: $0) }
        self.htmlData = record.html_data.flatMap { Data(base64Encoded: $0) }
        self.rtfdData = record.rtfd_data.flatMap { Data(base64Encoded: $0) }
        self.localData = nil
    }
}
extension ClipboardItem {
    var revealableFileURL: URL? {
        FileAccessStore.shared.resolvedURL(for: id, fallback: originalFileURL)
    }
}