import Foundation

struct ClipboardFolder: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
