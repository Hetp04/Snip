import SwiftUI
import UIKit

// MARK: - Neumorphic Shadow View Modifier

extension View {
    func softInnerShadow<S: Shape>(_ content: S, darkShadow: Color, lightShadow: Color, spread: CGFloat, radius: CGFloat) -> some View {
        self.overlay(
            content
                .stroke(darkShadow, lineWidth: spread)
                .blur(radius: radius)
                .offset(x: radius / 2, y: radius / 2)
                .mask(content.fill(style: FillStyle(eoFill: true)))
        )
        .overlay(
            content
                .stroke(lightShadow, lineWidth: spread)
                .blur(radius: radius)
                .offset(x: -radius / 2, y: -radius / 2)
                .mask(content.fill(style: FillStyle(eoFill: true)))
        )
    }
}

// MARK: - iOS Theme Tokens

enum IOSTheme {
    static let neoBase = Color(hex: "#FEFEFD") // Light off-white base
    static let neoContent = Color(hex: "#FEFEFD") // Light off-white content
    static let textPrimary = Color(hex: "#37352F")
    static let textSecondary = Color(hex: "#787774")
    static let textTertiary = Color(hex: "#B4B4B0")
    static let card = Color.white
    static let accent = Color(hex: "#2383E2")
    static let starActive = Color(hex: "#DFAB01")
    static let folderBg = Color(hex: "#F7F7F5")

    static func appHeaderGradient(for appName: String, fallbackColor: Color) -> (Color, Color) {
        let fadeTo = Color.white
        switch appName.lowercased() {
        case "google chrome", "chrome": return (Color(hex: "#FDEFE5"), fadeTo)
        case "slack": return (Color(hex: "#F4E8F9"), fadeTo)
        case "figma": return (Color(hex: "#FFECE7"), fadeTo)
        case "terminal", "iterm", "iterm2": return (Color(hex: "#E5E9EC"), fadeTo)
        case "safari": return (Color(hex: "#E8F3FD"), fadeTo)
        case "xcode": return (Color(hex: "#EAF2FD"), fadeTo)
        case "tableplus": return (Color(hex: "#FFF2E2"), fadeTo)
        case "code", "vs code", "visual studio code": return (Color(hex: "#E8F3FD"), fadeTo)
        case "notes": return (Color(hex: "#FFF7E0"), fadeTo)
        case "finder": return (Color(hex: "#EAF2FD"), fadeTo)
        case "messages": return (Color(hex: "#E9F9EE"), fadeTo)
        default: return (fallbackColor.opacity(0.12), fadeTo)
        }
    }
}
