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
    /// Versioned checksum of the portable rich payload.  This is metadata,
    /// not a rendering hint: receivers use it to reject corrupt or incomplete
    /// rich-text transfers before replacing their local representation.
    var richPayloadChecksum: String? = nil
    var richPayloadVersion: Int? = nil
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

    /// A single source of truth for behavior.  `contentType` describes the
    /// original capture; the available portable representations describe what
    /// can safely be rendered, edited and copied on this device.
    var hasPortableRichText: Bool {
        contentType == .richText || rtfData != nil || htmlData != nil || rtfdData != nil
    }

    var preferredRichTextData: Data? { rtfdData ?? rtfData ?? htmlData }
}

/// Resolves an app icon by stable bundle ID first and normalized app name as a
/// fallback. A card can therefore reuse a valid icon from any other capture of
/// the same app instead of showing a placeholder because one old record lacked
/// its own copy of the PNG.
struct ClipboardAppIconIndex {
    private var byBundleID: [String: Data] = [:]
    private var byName: [String: Data] = [:]

    init(items: [ClipboardItem]) {
        for item in items {
            guard let data = item.appIconData, !data.isEmpty else { continue }
            if let bundleID = item.sourceAppBundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !bundleID.isEmpty {
                byBundleID[bundleID.lowercased(), default: data] = byBundleID[bundleID.lowercased()] ?? data
            }
            let name = Self.normalizedName(item.sourceAppName)
            guard !name.isEmpty else { continue }
            byName[name, default: data] = byName[name] ?? data
        }
    }

    func iconData(for item: ClipboardItem) -> Data? {
        if let data = item.appIconData, !data.isEmpty { return data }
        if let bundleID = item.sourceAppBundleID?.lowercased(), let data = byBundleID[bundleID] { return data }
        return byName[Self.normalizedName(item.sourceAppName)]
    }

    func iconData(appName: String) -> Data? { byName[Self.normalizedName(appName)] }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }
}
