import Foundation

enum SyncStatus: String, Codable { case pending, synced, failed }

enum OCRStatus: String, Codable {
    case pending
    case done
    case none
    case failed
}

struct ClipboardItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var contentType: ContentType
    var contentText: String?
    var sourceAppName: String
    var sourceAppBundleID: String?
    var appIconData: Data? = nil
    var folderIDs: Set<UUID> = []
    var isPinned: Bool = false
    var createdAt: Date = Date()
    /// Local modification time used for deterministic last-writer-wins conflict
    /// resolution across the user's devices.
    var updatedAt: Date? = nil
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
    var detectedLanguage: String? = nil
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var ocrStatus: OCRStatus = .none
    var ocrText: String? = nil
    var searchContext: String? = nil
    var contextSourceHash: String? = nil
    var rawEmbedding: [Double]? = nil
    var embedding: [Double]? = nil
    var embeddingStatus: String = "pending"

    var isQueueHead: Bool { queuePosition == 0 }
    var previewText: String? { contentText.map { String($0.prefix(280)) } ?? fileName }
    func queuePreviewText() -> String { previewText ?? fileName ?? "Unknown item" }
    var searchableText: String { [rawSearchableText, searchContext].compactMap { $0 }.joined(separator: "\n") }
    var rawSearchableText: String { [contentText, ocrText, fileName, sourceAppName, detectedLanguage].compactMap { $0 }.joined(separator: "\n") }
    var bucket: String? {
        switch contentType {
        case .image: return AppConstants.Bucket.images
        case .video: return AppConstants.Bucket.videos
        case .file: return AppConstants.Bucket.files
        case .text, .richText, .url: return nil
        }
    }
    var revealableFileURL: URL? { FileAccessStore.shared.resolvedURL(for: id, fallback: originalFileURL) }
}
