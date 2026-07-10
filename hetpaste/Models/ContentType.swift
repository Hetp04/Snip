import Foundation
enum ContentType: String, Codable, CaseIterable {
    case text
    case richText
    case image
    case video
    case file
    case url
}