import Foundation
enum Formatters {
    nonisolated static func fileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }
}