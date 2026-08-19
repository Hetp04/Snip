import Foundation

struct Chain: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct ChainItem: Identifiable, Equatable, Codable {
    var id: UUID
    var chainID: UUID
    var snippetID: UUID
    var position: Int
}
