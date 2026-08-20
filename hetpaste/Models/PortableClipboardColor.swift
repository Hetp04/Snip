import Foundation

/// A standard, platform-neutral color representation. Unlike a source app's
/// private pasteboard type, this can be reconstructed on every Sniphet target.
struct PortableClipboardColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func parse(_ value: String?) -> PortableClipboardColor? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if text.hasPrefix("#") || [3, 6, 8].contains(text.count) {
            let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
            guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit),
                  let number = UInt64(hex, radix: 16) else { return parseRGB(text) }
            switch hex.count {
            case 3:
                return .init(red: Double((number >> 8) * 17) / 255, green: Double((number >> 4 & 0xF) * 17) / 255, blue: Double((number & 0xF) * 17) / 255, alpha: 1)
            case 6:
                return .init(red: Double(number >> 16) / 255, green: Double(number >> 8 & 0xFF) / 255, blue: Double(number & 0xFF) / 255, alpha: 1)
            default:
                let alpha = Double((number >> 24) & 0xFF) / 255
                let red = Double((number >> 16) & 0xFF) / 255
                let green = Double((number >> 8) & 0xFF) / 255
                let blue = Double(number & 0xFF) / 255
                return .init(red: red, green: green, blue: blue, alpha: alpha)
            }
        }
        return parseRGB(text)
    }

    private static func parseRGB(_ text: String) -> PortableClipboardColor? {
        guard text.hasPrefix("rgb(" ) || text.hasPrefix("rgba(") else { return nil }
        let values = text.replacingOccurrences(of: "rgba(", with: "")
            .replacingOccurrences(of: "rgb(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 3 || values.count == 4,
              let red = values[0], let green = values[1], let blue = values[2] else { return nil }
        let alpha = values.count == 4 ? (values[3] ?? 1) : 1
        guard (0...255).contains(red), (0...255).contains(green), (0...255).contains(blue), (0...1).contains(alpha) else { return nil }
        return .init(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }
}
