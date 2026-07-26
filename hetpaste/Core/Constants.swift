import Foundation
enum AppConstants {
    static let appName = "hetpaste"
    static let supabaseURL: URL = {
        guard
            let raw = infoValue(for: "SUPABASE_URL"),
            let url = URL(string: raw)
        else {
            fatalError("""
            Missing SUPABASE_URL. Add it to Config.xcconfig and map it in Info.plist.
            See README / Config.example.xcconfig for setup.
            """)
        }
        return url
    }()
    static let supabaseAnonKey: String = {
        guard let key = infoValue(for: "SUPABASE_ANON_KEY"), !key.isEmpty else {
            fatalError("""
            Missing SUPABASE_ANON_KEY. Add it to Config.xcconfig and map it in Info.plist.
            See README / Config.example.xcconfig for setup.
            """)
        }
        return key
    }()
    enum Bucket {
        static let images = "clipboard-images"
        static let files = "clipboard-files"
        static let videos = "clipboard-videos"
        static let previews = "clipboard-previews"
    }
    static let clipboardTable = "clipboard_items"
    static let foldersTable = "folders"
    static let chainsTable = "chains"
    static let chainItemsTable = "chain_items"
    private static func infoValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}