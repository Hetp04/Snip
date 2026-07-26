# Soft Neumorphic Icon System

A premium icon component system for SwiftUI that creates realistic depth and elevation using Apple's modern design language principles.

## Design Philosophy

The soft neumorphic icon system is built around these core principles:

### Surface & Material
- Light matte surface with minimal contrast
- Elements appear sculpted from a single soft ceramic/acrylic surface
- No hard borders, sharp edges, or high-contrast elements
- Avoid glossy or metallic reflections

### Depth Hierarchy
Build depth using **multiple elevation levels** instead of single large shadows:

1. **Ambient Shadow**: Broad, soft shadow that creates overall separation
2. **Contact Shadow**: Tight shadow that anchors the object to the surface
3. **Top Highlight**: Subtle light edge that simulates environmental lighting
4. **Edge Darkening**: Gentle darkening to define volume

### Lighting Model
**Single consistent light source from upper-left:**
- Top edges receive soft highlights
- Left edges are slightly brighter
- Bottom-right edges become gradually darker
- Shadows always fall toward lower-right

### Shadow System
Never use a single shadow. Always combine:

**Ambient Shadow:**
- Large blur radius
- Low opacity (0.2-0.25)
- Wide spread
- Creates spatial separation

**Contact Shadow:**
- Smaller blur radius
- Slightly darker (0.15-0.2 opacity)
- Concentrated near object
- Creates sense of weight

---

## Components

### 1. SoftNeumorphicIcon

The main icon component with full depth and lighting system.

```swift
SoftNeumorphicIcon(
    image: NSImage?,              // Actual app icon
    fallbackSystemName: "app.fill", // SF Symbol fallback
    fallbackColor: .blue,         // Color for fallback
    size: 48,                     // Icon size in points
    elevation: .medium,           // Elevation level
    isPressed: false,             // Press state
    isHovered: false              // Hover state
)
```

**Usage Example:**

```swift
// App icon with actual image
SoftNeumorphicIcon(
    image: IconCache.shared.cachedAppIcon(bundleID: "com.apple.Safari"),
    fallbackSystemName: "safari",
    fallbackColor: Color(hex: "#006CFF"),
    size: 48,
    elevation: .medium
)

// SF Symbol icon
SoftNeumorphicIcon(
    image: nil,
    fallbackSystemName: "terminal",
    fallbackColor: Color(hex: "#1A1A1A"),
    size: 48,
    elevation: .medium
)
```

### 2. SoftNeumorphicIconCompact

Simplified version for small UI contexts (badges, lists, toolbar).

```swift
SoftNeumorphicIconCompact(
    image: NSImage?,
    fallbackSystemName: "app.fill",
    fallbackColor: .blue,
    size: 20
)
```

**Usage Example:**

```swift
// Small app badge in a list
SoftNeumorphicIconCompact(
    image: headerIcon,
    fallbackSystemName: "app.fill",
    fallbackColor: appIconColor,
    size: 20
)
```

### 3. SoftNeumorphicIconButton

Interactive icon that responds to hover and press states with spring animations.

```swift
SoftNeumorphicIconButton(
    image: nil,
    fallbackSystemName: "star.fill",
    fallbackColor: Color(hex: "#FFD700"),
    size: 48,
    elevation: .medium,
    action: {
        // Handle tap
    }
)
```

**Features:**
- Automatic hover detection
- Press state with scale animation
- Spring-based transitions
- Physical feel

---

## Elevation Levels

Choose elevation based on visual hierarchy:

### `.low` - Subtle depth
- Use for: Secondary icons, list items
- Ambient shadow: 4pt blur
- Contact shadow: 2pt blur

### `.medium` (recommended default)
- Use for: Primary icons, cards
- Ambient shadow: 8pt blur
- Contact shadow: 3pt blur

### `.high` - Prominent elevation
- Use for: Featured icons, important actions
- Ambient shadow: 12pt blur
- Contact shadow: 4pt blur

### `.floating` - Maximum elevation
- Use for: Floating UI, modals, overlays
- Ambient shadow: 18pt blur
- Contact shadow: 6pt blur

**Example:**

```swift
// Low elevation for sidebar icons
SoftNeumorphicIcon(image: icon, size: 32, elevation: .low)

// Medium elevation for main content
SoftNeumorphicIcon(image: icon, size: 48, elevation: .medium)

// High elevation for featured items
SoftNeumorphicIcon(image: icon, size: 64, elevation: .high)

// Floating for modals
SoftNeumorphicIcon(image: icon, size: 80, elevation: .floating)
```

---

## Interactive States

### Hover State
When `isHovered = true`:
- Ambient shadow expands (+20% radius)
- Contact shadow strengthens (+15% opacity)
- Highlight becomes more visible (+10% opacity)
- Smooth spring animation

### Press State
When `isPressed = true`:
- Icon scales down to 96%
- Shadows reduce in size (-40% radius)
- Shadow opacity decreases
- Creates "pushed in" effect

**Manual State Example:**

```swift
struct AppIconView: View {
    @State private var isHovered = false
    
    var body: some View {
        SoftNeumorphicIcon(
            image: appIcon,
            size: 48,
            isHovered: isHovered
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
    }
}
```

---

## View Modifier

Apply soft neumorphic styling to any custom view:

```swift
MyCustomView()
    .softNeumorphicIcon(size: 48, elevation: .medium)
```

**Example:**

```swift
Text("AB")
    .font(.system(size: 24, weight: .bold))
    .foregroundColor(.blue)
    .softNeumorphicIcon(size: 48, elevation: .medium)
```

---

## Size Recommendations

| Context | Size | Component | Elevation |
|---------|------|-----------|-----------|
| Toolbar icon | 16-20pt | Compact | Low |
| List badge | 20-24pt | Compact | Low |
| Sidebar icon | 28-32pt | Icon | Low |
| Card header | 40-48pt | Icon | Medium |
| Featured icon | 64-80pt | Icon | High |
| Hero element | 96-128pt | Icon | Floating |

---

## Integration Examples

### In ClipboardItemRow

```swift
// Large header icon
private var largeHeaderAppIcon: some View {
    SoftNeumorphicIcon(
        image: headerIcon,
        fallbackSystemName: appIconName,
        fallbackColor: appIconColor,
        size: 48,
        elevation: .medium
    )
}

// Compact badge
private var appBadge: some View {
    SoftNeumorphicIconCompact(
        image: headerIcon,
        fallbackSystemName: appIconName,
        fallbackColor: appIconColor,
        size: 20
    )
}
```

### Interactive Toolbar

```swift
HStack(spacing: 16) {
    SoftNeumorphicIconButton(
        image: nil,
        fallbackSystemName: "star.fill",
        fallbackColor: .yellow,
        size: 32,
        elevation: .low,
        action: { toggleFavorite() }
    )
    
    SoftNeumorphicIconButton(
        image: nil,
        fallbackSystemName: "trash",
        fallbackColor: .red,
        size: 32,
        elevation: .low,
        action: { deleteItem() }
    )
}
```

### App Grid

```swift
LazyVGrid(columns: columns, spacing: 24) {
    ForEach(apps) { app in
        SoftNeumorphicIcon(
            image: app.icon,
            fallbackSystemName: app.symbolName,
            fallbackColor: app.color,
            size: 64,
            elevation: .medium
        )
    }
}
.padding()
.background(Color(hex: "#F5F5F0"))
```

---

## Color Utilities

### adjustBrightness(by:)
Adjusts color brightness while preserving hue and saturation:

```swift
let lighterColor = Color.blue.adjustBrightness(by: 0.1)
let darkerColor = Color.blue.adjustBrightness(by: -0.1)
```

### isLight
Determines if a color is light or dark for contrast decisions:

```swift
if backgroundColor.isLight {
    // Use dark text
} else {
    // Use light text
}
```

---

## Best Practices

### DO ✓
- Use consistent elevation levels across similar UI contexts
- Apply single light source direction (upper-left)
- Combine ambient + contact shadows
- Use generous corner radii (20-25% of size)
- Animate state changes with spring animations
- Scale shadows proportionally with icon size

### DON'T ✗
- Mix different lighting directions
- Use single shadow layers
- Apply hard borders or outlines
- Use pure black shadows
- Create high-contrast gradients
- Ignore hover/press states

---

## Theme Integration

The system integrates with your app's Theme:

```swift
// Use theme colors for fallbacks
SoftNeumorphicIcon(
    image: nil,
    fallbackSystemName: "app.fill",
    fallbackColor: Theme.accent,  // ← Theme color
    size: 48
)
```

---

## Performance Notes

- Icons use efficient shadow rendering
- NSImage caching via IconCache
- Compact variant for performance-critical contexts
- Animations use spring physics (no timers)
- Scales well from 16pt to 128pt

---

## Example: Full Implementation

```swift
struct AppIconCard: View {
    let app: AppModel
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 12) {
            SoftNeumorphicIcon(
                image: IconCache.shared.cachedAppIcon(bundleID: app.bundleID),
                fallbackSystemName: app.symbolName,
                fallbackColor: app.color,
                size: 64,
                elevation: .medium,
                isPressed: isPressed,
                isHovered: isHovered
            )
            
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(16)
        .background(Color(hex: "#F5F5F0"))
        .cornerRadius(16)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                app.launch()
            }
        }
    }
}
```

---

## Troubleshooting

**Icons look too dark:**
- Check ambient shadow opacity (should be 0.2-0.3)
- Verify background color is light (#F5F5F0 recommended)

**Shadows don't show:**
- Ensure parent view has sufficient padding
- Check if shadows are being clipped
- Verify color opacity isn't too low

**Performance issues:**
- Use SoftNeumorphicIconCompact for lists
- Cache NSImages via IconCache
- Reduce elevation for many icons

**Hover states not working:**
- Ensure Button uses `.plain` style
- Check parent isn't blocking hit testing
- Verify animation is applied

---

## Credits

Inspired by Apple's design language across visionOS, macOS Sonoma, and iOS 17+. Implements realistic depth perception through multiple shadow layers, consistent directional lighting, and subtle material properties.
