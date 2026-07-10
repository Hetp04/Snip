import Foundation
struct ClipboardFolder: Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}
struct ClipboardFolderRecord: Codable {
    let id: String
    let name: String
    let created_at: String?
    let updated_at: String?
}
struct ClipboardFolderInsertRecord: Codable {
    let id: String
    let name: String
}
struct ClipboardFolderNameUpdate: Codable {
    let name: String
}
struct ClipboardItemFolderUpdate: Codable {
    let folder_id: String?
}
extension ClipboardFolder {
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
    init(record: ClipboardFolderRecord) {
        self.id = UUID(uuidString: record.id) ?? UUID()
        self.name = record.name
        if let created = record.created_at {
            self.createdAt = Self.isoFormatter.date(from: created)
                ?? Self.isoFormatterNoFraction.date(from: created)
                ?? Date()
        } else {
            self.createdAt = Date()
        }
        if let updated = record.updated_at {
            self.updatedAt = Self.isoFormatter.date(from: updated)
                ?? Self.isoFormatterNoFraction.date(from: updated)
                ?? Date()
        } else {
            self.updatedAt = self.createdAt
        }
    }
}