import Foundation

enum WardrobeSource: String, Codable { case external, internalReference = "internal_reference" }

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
    var fileExtension: String?
    var createdAt: Date = Date()
    var updatedAt: Date? = nil
    var localData: Data?
    var originalFilePath: String?

    var previewText: String? { content.map { String($0.prefix(280)) } ?? fileName }
    var bucket: String? {
        switch contentType {
        case .image, .video, .file: return "wardrobe-items"
        case .text, .richText, .url: return nil
        }
    }
}
