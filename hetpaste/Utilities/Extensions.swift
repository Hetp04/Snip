import AppKit
import Foundation
import SwiftUI
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    static func parseColor(from string: String) -> Color? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") || (trimmed.count == 6 && trimmed.allSatisfy { $0.isHexDigit }) || (trimmed.count == 3 && trimmed.allSatisfy { $0.isHexDigit }) {
            let hexStr = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
            if [3, 6, 8].contains(hexStr.count) && hexStr.allSatisfy({ $0.isHexDigit }) {
                return Color(hex: hexStr)
            }
        }
        if trimmed.hasPrefix("rgb(") || trimmed.hasPrefix("rgba(") {
            let components = trimmed
                .replacingOccurrences(of: "rgba(", with: "")
                .replacingOccurrences(of: "rgb(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count >= 3 {
                if let r = Double(components[0]), let g = Double(components[1]), let b = Double(components[2]) {
                    var a: Double = 1.0
                    if components.count == 4, let alpha = Double(components[3]) { a = alpha }
                    let divisor: Double = 255.0
                    return Color(.sRGB, red: r / divisor, green: g / divisor, blue: b / divisor, opacity: a)
                }
            }
        }
        if trimmed.hasPrefix("hsl(") || trimmed.hasPrefix("hsla(") {
            let components = trimmed
                .replacingOccurrences(of: "hsla(", with: "")
                .replacingOccurrences(of: "hsl(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "") }
            if components.count >= 3 {
                if let h = Double(components[0]), let s = Double(components[1]), let l = Double(components[2]) {
                    var a: Double = 1.0
                    if components.count == 4, let alpha = Double(components[3]) { a = alpha }
                    return Color(hue: h / 360.0, saturation: s / 100.0, lightness: l / 100.0, opacity: a)
                }
            }
        }
        return nil
    }
    init(hue: Double, saturation: Double, lightness: Double, opacity: Double = 1.0) {
        let h = hue
        let s = saturation
        let l = lightness
        let r, g, b: Double
        if s == 0 {
            r = l; g = l; b = l
        } else {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            r = Color.hueToRGB(p: p, q: q, t: h + 1.0/3.0)
            g = Color.hueToRGB(p: p, q: q, t: h)
            b = Color.hueToRGB(p: p, q: q, t: h - 1.0/3.0)
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
    private static func hueToRGB(p: Double, q: Double, t: Double) -> Double {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0/6.0 { return p + (q - p) * 6.0 * t }
        if t < 1.0/2.0 { return q }
        if t < 2.0/3.0 { return p + (q - p) * (2.0/3.0 - t) * 6.0 }
        return p
    }
    var isLight: Bool {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB)?.cgColor.components else { return true }
        let r = components[0]
        let g = components.count > 1 ? components[1] : r
        let b = components.count > 2 ? components[2] : r
        let brightness = (r * 299 + g * 587 + b * 114) / 1000
        return brightness > 0.5
    }
}
extension NSImage {
    func dominantAccentColor() -> Color? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = 24
        let height = 24
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var raw = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var weightedRed: Double = 0
        var weightedGreen: Double = 0
        var weightedBlue: Double = 0
        var totalWeight: Double = 0
        for pixel in stride(from: 0, to: raw.count, by: bytesPerPixel) {
            let red = Double(raw[pixel]) / 255.0
            let green = Double(raw[pixel + 1]) / 255.0
            let blue = Double(raw[pixel + 2]) / 255.0
            let alpha = Double(raw[pixel + 3]) / 255.0
            guard alpha > 0.12 else { continue }
            let maxChannel = max(red, max(green, blue))
            let minChannel = min(red, min(green, blue))
            let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel
            let brightness = maxChannel
            let weight = alpha * max(0.2, saturation) * max(0.35, brightness)
            weightedRed += red * weight
            weightedGreen += green * weight
            weightedBlue += blue * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        var red = weightedRed / totalWeight
        var green = weightedGreen / totalWeight
        var blue = weightedBlue / totalWeight
        let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        saturation = max(saturation, 0.45)
        brightness = min(max(brightness, 0.42), 0.72)
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: 1)
    }
}
enum Theme {
    static let bg = Color.white
    static let sidebar = Color(hex: "#F7F7F5")
    static let card = Color.white
    static let cardHover = Color(hex: "#F7F7F5")
    static let selection = Color(hex: "#EBEBEA")
    static let codeBlock = Color(hex: "#1E1E1E")
    static let codeBlockBorder = Color(hex: "#2D2D2D")
    static let codeText = Color(hex: "#D4D4D4")
    static let codeGutter = Color(hex: "#161B22")
    static let border = Color(hex: "#E8E8E5")
    static let divider = Color(hex: "#E8E8E5")
    static let textPrimary = Color(hex: "#37352F")
    static let textSecondary = Color(hex: "#787774")
    static let textTertiary = Color(hex: "#B4B4B0")
    static let accent = Color(hex: "#2383E2")
    static let starActive = Color(hex: "#DFAB01")
    static let syncGreen = Color(hex: "#0F7B6C")
    static let searchBg = Color(hex: "#F1F1EF")
}
enum AppVisual {
    private static let iconCache = NSCache<NSString, NSImage>()
    static func lookup(_ appName: String, bundleID: String? = nil) -> (symbol: String, color: Color, icon: NSImage?) {
        var systemIcon: NSImage? = nil
        if let bidStr = bundleID, !bidStr.isEmpty {
            if let disk = IconCache.shared.cachedAppIcon(bundleID: bidStr) {
                systemIcon = disk
            } else if let mem = iconCache.object(forKey: bidStr as NSString) {
                systemIcon = mem
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bidStr) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 64, height: 64)
                iconCache.setObject(icon, forKey: bidStr as NSString)
                IconCache.shared.saveAppIcon(icon, bundleID: bidStr)
                systemIcon = icon
            }
        }
        switch appName.lowercased() {
        case "terminal", "iterm", "iterm2":            return ("terminal.fill", Color(hex: "#1A1A1A"), systemIcon)
        case "safari":                                  return ("safari.fill", Color(hex: "#006CFF"), systemIcon)
        case "slack":                                   return ("ellipsis.message.fill", Color(hex: "#E01E5A"), systemIcon)
        case "xcode":                                   return ("hammer.fill", Color(hex: "#147EFB"), systemIcon)
        case "tableplus":                               return ("cylinder.split.1x2.fill", Color(hex: "#F5A623"), systemIcon)
        case "figma":                                   return ("paintbrush.pointed.fill", Color(hex: "#A259FF"), systemIcon)
        case "code", "vs code", "visual studio code":   return ("chevron.left.forwardslash.chevron.right", Color(hex: "#0066B8"), systemIcon)
        case "google chrome", "chrome":                 return ("globe", Color(hex: "#4285F4"), systemIcon)
        case "notes":                                   return ("note.text", Color(hex: "#FFCC02"), systemIcon)
        case "screenshot", "screen capture":            return ("camera.fill", Color(hex: "#6C7A89"), systemIcon)
        case "mail":                                    return ("envelope.fill", Color(hex: "#3B82F6"), systemIcon)
        case "notion":                                  return ("square.text.square.fill", Color(hex: "#191919"), systemIcon)
        case "finder":                                  return ("folder.fill", Color(hex: "#3B82F6"), systemIcon)
        case "messages":                                return ("message.fill", Color(hex: "#34C759"), systemIcon)
        case "preview":                                 return ("doc.viewfinder", Color(hex: "#6C7A89"), systemIcon)
        default:                                        return ("app.dashed", Color(hex: "#9B9B9B"), systemIcon)
        }
    }
}
extension Date {
    func relativeString() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        if interval < 60 { return "Just now" }
        if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
        if interval < 172800 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }
    func detailString() -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if calendar.isDateInYesterday(self) {
            formatter.dateFormat = "'Yesterday at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        }
        return formatter.string(from: self)
    }
}