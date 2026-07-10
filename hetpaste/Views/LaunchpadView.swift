import AppKit
import SwiftUI
struct LaunchpadView: View {
    let items: [ClipboardItem]
    let onSelectApp: (String?) -> Void
    let onSelectCategory: (ContentType) -> Void
    private let columns = [
        GridItem(.adaptive(minimum: 88, maximum: 112), spacing: 26)
    ]
    private var appEntries: [AppEntry] {
        Dictionary(grouping: items, by: { $0.sourceAppName })
            .map { name, groupedItems in
                let first = groupedItems.first
                let visual = AppVisual.lookup(name, bundleID: first?.sourceAppBundleID)
                return AppEntry(
                    name: name,
                    sfSymbol: visual.symbol,
                    color: visual.color,
                    itemCount: groupedItems.count,
                    icon: visual.icon
                )
            }
            .sorted {
                if $0.itemCount == $1.itemCount { return $0.name < $1.name }
                return $0.itemCount > $1.itemCount
            }
    }
    private var categories: [CategoryEntry] {
        [
            CategoryEntry(name: "Text", sfSymbol: "text.alignleft", color: Theme.accent, type: .text),
            CategoryEntry(name: "Rich Text", sfSymbol: "doc.richtext", color: Theme.accent, type: .richText),
            CategoryEntry(name: "Images", sfSymbol: "photo", color: Theme.accent, type: .image),
            CategoryEntry(name: "Files", sfSymbol: "doc", color: Theme.accent, type: .file),
            CategoryEntry(name: "Links", sfSymbol: "link", color: Theme.accent, type: .url)
        ]
        .filter { category in
            items.contains { $0.contentType == category.type }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !categories.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Types")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                            ForEach(categories) { category in
                                LaunchpadIcon(
                                    title: category.name,
                                    sfSymbol: category.sfSymbol,
                                    color: category.color,
                                    image: nil
                                ) {
                                    onSelectCategory(category.type)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Applications")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(appEntries) { app in
                            LaunchpadIcon(
                                title: app.name,
                                sfSymbol: app.sfSymbol,
                                color: app.color,
                                image: app.icon
                            ) {
                                onSelectApp(app.name)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .background(Theme.bg)
    }
}
struct AppEntry: Identifiable {
    let id = UUID()
    let name: String
    let sfSymbol: String
    let color: Color
    let itemCount: Int
    let icon: NSImage?
}
struct CategoryEntry: Identifiable {
    let id = UUID()
    let name: String
    let sfSymbol: String
    let color: Color
    let type: ContentType
}
private struct LaunchpadIcon: View {
    let title: String
    let sfSymbol: String
    let color: Color
    let image: NSImage?
    let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(color)
                            Image(systemName: sfSymbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .shadow(color: Color.black.opacity(image == nil ? 0.04 : 0.12), radius: 3, y: 1)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 86, idealWidth: 86, maxWidth: 86, minHeight: 30, alignment: .top)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Theme.selection.opacity(0.65) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}