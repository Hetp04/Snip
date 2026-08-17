import Foundation

struct ClipboardFolder: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}
