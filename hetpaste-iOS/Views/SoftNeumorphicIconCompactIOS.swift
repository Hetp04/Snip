import SwiftUI
import UIKit

struct SoftNeumorphicIconCompactIOS: View {
    let iconData: Data?
    let appName: String
    let fallbackSystemName: String
    let fallbackColor: Color

    private var uiImage: UIImage? {
        guard let iconData else { return nil }
        return UIImage(data: iconData)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .softInnerShadow(
                    RoundedRectangle(cornerRadius: 8, style: .continuous),
                    darkShadow: Color(hex: "#A3B1C6").opacity(0.3),
                    lightShadow: Color.white.opacity(0.8),
                    spread: 0.05,
                    radius: 2
                )

            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: resolvedFallbackIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resolvedFallbackIcon: String {
        switch appName.lowercased() {
        case "terminal", "iterm", "iterm2": return "terminal"
        case "safari": return "safari"
        case "slack": return "number.square"
        case "xcode": return "hammer"
        case "tableplus": return "cylinder.split.1x2"
        case "figma": return "paintbrush.pointed"
        case "chrome", "google chrome": return "globe"
        case "notes": return "note.text"
        case "messages": return "message.fill"
        default: return fallbackSystemName
        }
    }
}
