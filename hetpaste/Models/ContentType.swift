import Foundation
enum ContentType: String, Codable, CaseIterable {
    case text
    case richText
    case image
    case video
    case file
    case url

    var searchFilterTitle: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Images"
        case .video: return "Videos"
        case .file: return "Files"
        case .url: return "Links"
        }
    }

    var searchFilterIcon: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .file: return "doc"
        case .url: return "link"
        }
    }
}
