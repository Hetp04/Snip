import Foundation
enum AppConstants {
    static let appName = "hetpaste"
    enum Bucket {
        static let images = "clipboard-images"
        static let files = "clipboard-files"
        static let videos = "clipboard-videos"
        static let previews = "clipboard-previews"
    }
    private static func infoValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
