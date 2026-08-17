import Foundation

struct Chain: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

struct ChainItem: Identifiable, Equatable, Codable {
    var id: UUID
    var chainID: UUID
    var snippetID: UUID
    var position: Int
}
