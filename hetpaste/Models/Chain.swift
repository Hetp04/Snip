import Foundation

// MARK: - Domain Models

struct Chain: Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

struct ChainItem: Identifiable, Equatable {
    var id: UUID
    var chainID: UUID
    var snippetID: UUID
    var position: Int
}

// MARK: - Supabase Record Types

struct ChainRecord: Codable {
    let id: String
    let name: String
    let created_at: String?
    let updated_at: String?
}

struct ChainInsertRecord: Codable {
    let id: String
    let name: String
}

struct ChainNameUpdate: Codable {
    let name: String
    let updated_at: String
}

struct ChainItemRecord: Codable {
    let id: String
    let chain_id: String
    let snippet_id: String
    let position: Int
    let created_at: String?
}

struct ChainItemInsertRecord: Codable {
    let id: String
    let chain_id: String
    let snippet_id: String
    let position: Int
}

// MARK: - Chain init from record

extension Chain {
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

    init(record: ChainRecord) {
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

// MARK: - ChainItem init from record

extension ChainItem {
    init(record: ChainItemRecord) {
        self.id = UUID(uuidString: record.id) ?? UUID()
        self.chainID = UUID(uuidString: record.chain_id) ?? UUID()
        self.snippetID = UUID(uuidString: record.snippet_id) ?? UUID()
        self.position = record.position
    }
}
