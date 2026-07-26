import Foundation
import SwiftUI

enum ContentCategory: String, CaseIterable, Equatable, Hashable {
    case text
    case url
    case image
    case code
    case color
    case file
    case richText
    case table
    case email
    case phone
    case pdf
    case video
    case audio
    case emoji
    case json
    
    var iconName: String {
        switch self {
        case .text: return "doc.plaintext"
        case .url: return "link"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.right"
        case .color: return "paintpalette"
        case .file: return "doc"
        case .richText: return "doc.richtext"
        case .table: return "tablecells"
        case .email: return "envelope"
        case .phone: return "phone"
        case .pdf: return "doc.richtext.fill"
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .emoji: return "face.smiling"
        case .json: return "curlybraces"
        }
    }
    
    var iconForeground: Color {
        switch self {
        case .text: return Color(hex: "#5C5C5C")
        case .url: return Color(hex: "#2980B9")
        case .image: return Color(hex: "#D35400")
        case .code: return Color(hex: "#E67E22")
        case .color: return Color(hex: "#E81123")
        case .file: return Color(hex: "#27AE60")
        case .richText: return Color(hex: "#8E44AD")
        case .table: return Color(hex: "#16A085")
        case .email: return Color(hex: "#C0392B")
        case .phone: return Color(hex: "#2C3E50")
        case .pdf: return Color(hex: "#C0392B")
        case .video: return Color(hex: "#E74C3C")
        case .audio: return Color(hex: "#F39C12")
        case .emoji: return Color(hex: "#F1C40F")
        case .json: return Color(hex: "#34495E")
        }
    }
    
    var iconBackground: Color {
        switch self {
        case .text: return Color(hex: "#F5F5F5")
        case .url: return Color(hex: "#EBF5FB")
        case .image: return Color(hex: "#FDF2E9")
        case .code: return Color(hex: "#FEF5E7")
        case .color: return Color(hex: "#FDE7E9")
        case .file: return Color(hex: "#EAFAF1")
        case .richText: return Color(hex: "#F5EEF8")
        case .table: return Color(hex: "#E8F8F5")
        case .email: return Color(hex: "#FDEDEC")
        case .phone: return Color(hex: "#EAECEE")
        case .pdf: return Color(hex: "#FDEDEC")
        case .video: return Color(hex: "#FDEDEC")
        case .audio: return Color(hex: "#FEF9E7")
        case .emoji: return Color(hex: "#FEF9E7")
        case .json: return Color(hex: "#EAECEE")
        }
    }
    
    static func detect(from item: ClipboardItem) -> ContentCategory {
        // 1. Files
        if item.contentType == .file {
            if let mime = item.mimeType?.lowercased() {
                if mime.contains("pdf") || item.fileName?.lowercased().hasSuffix(".pdf") == true {
                    return .pdf
                }
                if mime.starts(with: "video") || item.fileName?.lowercased().hasSuffix(".mp4") == true || item.fileName?.lowercased().hasSuffix(".mov") == true {
                    return .video
                }
                if mime.starts(with: "audio") || item.fileName?.lowercased().hasSuffix(".mp3") == true || item.fileName?.lowercased().hasSuffix(".wav") == true {
                    return .audio
                }
                if mime.starts(with: "image") {
                    return .image
                }
            }
            return .file
        }
        
        // 2. Direct Mappings
        if item.contentType == .image { return .image }
        if item.contentType == .video { return .video }
        if item.contentType == .richText { return .richText }
        if item.contentType == .url { return .url }
        
        let text = item.contentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // 3. Code & JSON (from detected language)
        if item.detectedLanguage != nil {
            if item.detectedLanguage?.lowercased() == "json" || (text.hasPrefix("{") && text.hasSuffix("}")) {
                return .json
            }
            return .code
        }
        
        guard !text.isEmpty else { return .text }
        
        // 4. Color detection
        if Color.parseColor(from: text) != nil {
            return .color
        }
        
        // 5. JSON fallback (simple heuristic)
        if (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]")) {
            if text.contains("\\\"") || text.contains("\":") {
                return .json
            }
        }
        
        // 6. Emoji (only emojis, very short)
        if text.count > 0 && text.count <= 5 {
            let isAllEmoji = text.unicodeScalars.allSatisfy { $0.properties.isEmojiPresentation }
            if isAllEmoji {
                return .emoji
            }
        }
        
        // 7. Table (heuristic: contains tabs and newlines)
        if text.contains("\t") && text.contains("\n") {
            return .table
        }
        
        // 8. Data Detectors for Link, Phone, Email
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
            let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            
            // If the entire text perfectly matches a single entity
            if let match = matches.first, match.range.length == text.utf16.count {
                if match.resultType == .link {
                    if let url = match.url, url.scheme == "mailto" {
                        return .email
                    }
                    return .url
                }
                if match.resultType == .phoneNumber {
                    return .phone
                }
            }
        } catch {}
        
        // Fallback
        return .text
    }
}
