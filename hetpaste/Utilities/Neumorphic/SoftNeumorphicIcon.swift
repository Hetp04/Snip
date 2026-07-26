//
//  SoftNeumorphicIcon.swift
//  hetpaste
//
//  Premium soft-neumorphic icon component system
//  Inspired by Apple's modern design language (visionOS, macOS, iOS)
//  Focus on realistic depth, layered lighting, and subtle shadows
//

import SwiftUI
import AppKit

// MARK: - Soft Neumorphic Icon Component

/// A premium soft-neumorphic icon wrapper that creates realistic depth and elevation
/// using multiple shadow layers, subtle gradients, and directional lighting.
///
/// Design principles:
/// - Light source from upper-left (consistent across all icons)
/// - Multiple elevation levels (ambient + contact shadows)
/// - Soft ceramic/matte acrylic material feel
/// - No hard borders or sharp edges
/// - Elements appear sculpted from a single surface
struct SoftNeumorphicIcon: View {
    let image: NSImage?
    let fallbackSystemName: String?
    let fallbackColor: Color
    let size: CGFloat
    var elevation: SoftElevation = .medium
    var isPressed: Bool = false
    var isHovered: Bool = false
    
    init(
        image: NSImage?,
        fallbackSystemName: String? = "app.fill",
        fallbackColor: Color = Color(hex: "#A3B1C6"),
        size: CGFloat = 48,
        elevation: SoftElevation = .medium,
        isPressed: Bool = false,
        isHovered: Bool = false
    ) {
        self.image = image
        self.fallbackSystemName = fallbackSystemName
        self.fallbackColor = fallbackColor
        self.size = size
        self.elevation = elevation
        self.isPressed = isPressed
        self.isHovered = isHovered
    }
    
    var body: some View {
        ZStack {
            // Base surface with inset effect
            baseSurface
            
            // Icon content with proper layering
            iconContent
                .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .frame(width: size, height: size)
    }
    
    // MARK: - Base Surface
    
    /// The foundational surface with soft inset depth effect
    private var baseSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(insetSurfaceGradient)
            // Inner shadow for inset/pressed-in effect
            .softInnerShadow(
                RoundedRectangle(cornerRadius: cornerRadius),
                darkShadow: innerDarkShadowColor,
                lightShadow: innerLightShadowColor,
                spread: innerShadowSpread,
                radius: innerShadowRadius
            )
    }
    
    // MARK: - Icon Content
    
    @ViewBuilder
    private var iconContent: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        } else if let systemName = fallbackSystemName {
            Image(systemName: systemName)
                .font(.system(size: iconSize * 0.5, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: fallbackIconGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    // MARK: - Computed Properties
    
    /// Corner radius scales with size for natural proportions
    private var cornerRadius: CGFloat {
        size * 0.23 // Generous radius for soft, inflated feel
    }
    
    /// Icon size is slightly smaller than container for proper spacing
    private var iconSize: CGFloat {
        size * 0.82
    }
    
    // MARK: - Inset Surface Gradient
    
    /// Gradient for inset effect - slightly darker in center
    private var insetSurfaceGradient: LinearGradient {
        let baseColor = Color.white
        let darkerShade = baseColor.adjustBrightness(by: -0.03)
        let lighterEdge = baseColor.adjustBrightness(by: 0.01)
        
        return LinearGradient(
            colors: [darkerShade, baseColor, lighterEdge],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Inner Shadow System (for inset effect)
    
    /// Dark inner shadow - creates depth at top-left
    private var innerDarkShadowColor: Color {
        let opacity: Double = isPressed ? 0.45 : (isHovered ? 0.40 : 0.35)
        return Color(hex: "#A3B1C6").opacity(opacity)
    }
    
    /// Light inner shadow - creates highlight at bottom-right
    private var innerLightShadowColor: Color {
        Color.white.opacity(isHovered ? 0.9 : 0.8)
    }
    
    /// Spread controls how far the shadow extends
    private var innerShadowSpread: CGFloat {
        let base = elevation.innerSpread()
        return isPressed ? base * 1.2 : (isHovered ? base * 0.9 : base)
    }
    
    /// Radius controls shadow blur
    private var innerShadowRadius: CGFloat {
        let base = elevation.innerRadius(for: size)
        return isPressed ? base * 1.1 : (isHovered ? base * 0.95 : base)
    }
    
    // MARK: - Fallback Icon Gradient
    
    private var fallbackIconGradient: [Color] {
        [
            fallbackColor,
            fallbackColor.adjustBrightness(by: -0.12)
        ]
    }
}

// MARK: - Elevation Levels

/// Defines different elevation levels for icons
/// Each level has specific inner shadow characteristics for realistic inset depth
enum SoftElevation {
    case low
    case medium
    case high
    case floating
    
    /// Inner shadow radius scales with icon size
    func innerRadius(for size: CGFloat) -> CGFloat {
        let scale = size / 48.0
        switch self {
        case .low: return 3 * scale
        case .medium: return 5 * scale
        case .high: return 7 * scale
        case .floating: return 10 * scale
        }
    }
    
    /// Inner shadow spread - how pronounced the inset is
    func innerSpread() -> CGFloat {
        switch self {
        case .low: return 0.04
        case .medium: return 0.08
        case .high: return 0.12
        case .floating: return 0.16
        }
    }
    
    // Legacy methods for backwards compatibility with compact variant
    func ambientRadius(for size: CGFloat) -> CGFloat {
        innerRadius(for: size)
    }
    
    func ambientOffset(for size: CGFloat) -> CGSize {
        .zero
    }
    
    func contactRadius(for size: CGFloat) -> CGFloat {
        innerRadius(for: size) * 0.5
    }
    
    func contactOffset(for size: CGFloat) -> CGSize {
        .zero
    }
}

// MARK: - Compact Icon Variants

/// Small icon variant (20-28pt) for compact UI contexts with inset effect
struct SoftNeumorphicIconCompact: View {
    let image: NSImage?
    let fallbackSystemName: String?
    let fallbackColor: Color
    let size: CGFloat
    var isHovered: Bool = false
    
    init(
        image: NSImage?,
        fallbackSystemName: String? = "app.fill",
        fallbackColor: Color = Color(hex: "#A3B1C6"),
        size: CGFloat = 20
    ) {
        self.image = image
        self.fallbackSystemName = fallbackSystemName
        self.fallbackColor = fallbackColor
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Simplified inset surface for small sizes
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color.white)
                .softInnerShadow(
                    RoundedRectangle(cornerRadius: size * 0.22),
                    darkShadow: Color(hex: "#A3B1C6").opacity(0.3),
                    lightShadow: Color.white.opacity(0.8),
                    spread: 0.05,
                    radius: 2
                )
            
            // Icon content
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.75, height: size * 0.75)
            } else if let systemName = fallbackSystemName {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundColor(fallbackColor)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Interactive Icon Button

/// An interactive icon that responds to hover and press states
struct SoftNeumorphicIconButton: View {
    let image: NSImage?
    let fallbackSystemName: String?
    let fallbackColor: Color
    let size: CGFloat
    var elevation: SoftElevation = .medium
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            action()
        }) {
            SoftNeumorphicIcon(
                image: image,
                fallbackSystemName: fallbackSystemName,
                fallbackColor: fallbackColor,
                size: size,
                elevation: elevation,
                isPressed: isPressed,
                isHovered: isHovered
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - View Extension

extension View {
    /// Apply soft neumorphic icon styling to any view
    func softNeumorphicIcon(
        size: CGFloat = 48,
        elevation: SoftElevation = .medium
    ) -> some View {
        self.modifier(SoftNeumorphicIconModifier(size: size, elevation: elevation))
    }
}

struct SoftNeumorphicIconModifier: ViewModifier {
    let size: CGFloat
    let elevation: SoftElevation
    
    func body(content: Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.adjustBrightness(by: -0.03),
                            Color.white,
                            Color.white.adjustBrightness(by: 0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .softInnerShadow(
                    RoundedRectangle(cornerRadius: size * 0.23),
                    darkShadow: Color(hex: "#A3B1C6").opacity(0.35),
                    lightShadow: Color.white.opacity(0.8),
                    spread: elevation.innerSpread(),
                    radius: elevation.innerRadius(for: size)
                )
            
            content
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Color Utilities

extension Color {
    /// Adjust brightness while maintaining hue and saturation
    func adjustBrightness(by amount: Double) -> Color {
        #if os(macOS)
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        let newBrightness = max(0, min(1, brightness + amount))
        
        return Color(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(newBrightness),
            opacity: Double(alpha)
        )
        #else
        // iOS implementation
        return self
        #endif
    }
}

// MARK: - Preview

#if DEBUG
struct SoftNeumorphicIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            // Different sizes
            HStack(spacing: 24) {
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "terminal",
                    fallbackColor: Color(hex: "#1A1A1A"),
                    size: 32,
                    elevation: .low
                )
                
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "safari",
                    fallbackColor: Color(hex: "#006CFF"),
                    size: 48,
                    elevation: .medium
                )
                
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "paintbrush.pointed",
                    fallbackColor: Color(hex: "#A259FF"),
                    size: 64,
                    elevation: .high
                )
                
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "hammer",
                    fallbackColor: Color(hex: "#147EFB"),
                    size: 80,
                    elevation: .floating
                )
            }
            
            // Interactive states
            HStack(spacing: 24) {
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "app.fill",
                    fallbackColor: Color(hex: "#A3B1C6"),
                    size: 48,
                    isHovered: false
                )
                .overlay(Text("Normal").font(.caption2).offset(y: 40))
                
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "app.fill",
                    fallbackColor: Color(hex: "#A3B1C6"),
                    size: 48,
                    isHovered: true
                )
                .overlay(Text("Hovered").font(.caption2).offset(y: 40))
                
                SoftNeumorphicIcon(
                    image: nil,
                    fallbackSystemName: "app.fill",
                    fallbackColor: Color(hex: "#A3B1C6"),
                    size: 48,
                    isPressed: true
                )
                .overlay(Text("Pressed").font(.caption2).offset(y: 40))
            }
            
            // Compact variant
            HStack(spacing: 16) {
                ForEach(["terminal", "safari", "paintbrush.pointed", "hammer", "app.fill"], id: \.self) { icon in
                    SoftNeumorphicIconCompact(
                        image: nil,
                        fallbackSystemName: icon,
                        fallbackColor: Color(hex: "#A3B1C6"),
                        size: 20
                    )
                }
            }
            
            // Interactive button
            SoftNeumorphicIconButton(
                image: nil,
                fallbackSystemName: "star.fill",
                fallbackColor: Color(hex: "#FFD700"),
                size: 48,
                elevation: .medium,
                action: {
                    print("Icon tapped!")
                }
            )
        }
        .padding(40)
        .frame(width: 600, height: 500)
        .background(Color(hex: "#F5F5F0"))
    }
}
#endif
