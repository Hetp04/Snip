import SwiftUI
import UIKit

private final class RichTextPreviewCache {
    static let shared = RichTextPreviewCache()
    private let cache = NSCache<NSString, NSAttributedString>()
    func value(for key: String) -> NSAttributedString? { cache.object(forKey: key as NSString) }
    func insert(_ value: NSAttributedString, for key: String) { cache.setObject(value, forKey: key as NSString) }
}

struct IOSClipboardCard: View {
    let item: ClipboardItem
    let resolvedAppIconData: Data?
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onQuickLook: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onOpenLink: () -> Void
    let onOpenLinkPreview: () -> Void
    let onEdit: () -> Void
    let onToggleFavorite: () -> Void

    private var menuCapabilities: ClipboardContextMenuCapabilities { item.contextMenuCapabilities }

    private var itemType: String {
        if let language = item.detectedLanguage, !language.isEmpty { return language.capitalized }
        switch item.contentType {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .video: return "Video"
        case .file: return "File"
        case .url: return "Link"
        }
    }

    private var relativeTime: String {
        item.createdAt.relativeString()
    }

    private var footerText: String {
        if let size = item.fileSize, size > 0 { return Formatters.fileSize(size) }
        if let content = item.contentText { return "\(content.count) chars" }
        return item.fileName ?? itemType
    }

    private var headerGradients: (Color, Color) {
        IOSTheme.appHeaderGradient(for: item.sourceAppName, fallbackColor: Color(uiColor: .systemGray))
    }

    private var portableColor: PortableClipboardColor? {
        guard item.contentType == .text || item.contentType == .richText else { return nil }
        return PortableClipboardColor.parse(item.contentText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (Matches Mac pasteHeader)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sourceAppName.isEmpty ? "Unknown" : item.sourceAppName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IOSTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(itemType) · \(relativeTime)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IOSTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                // Mac App Icon Badge
                SoftNeumorphicIconCompactIOS(
                    iconData: resolvedAppIconData,
                    appName: item.sourceAppName,
                    fallbackSystemName: "app.fill",
                    fallbackColor: Color(uiColor: .systemGray)
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [headerGradients.0, headerGradients.1],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            // Body preview (Neumorphic inner shadow just like Mac pasteContent)
            ZStack {
                IOSTheme.neoContent
                    .softInnerShadow(
                        RoundedRectangle(cornerRadius: 14, style: .continuous),
                        darkShadow: Color(hex: "#A3B1C6").opacity(0.35),
                        lightShadow: Color.white,
                        spread: 0.04,
                        radius: 4
                    )

                preview
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(height: 92) // Mac exact height
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            // Footer
            HStack(spacing: 4) {
                Text(footerText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IOSTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(IOSTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Copy snippet")
                Button(action: onToggleFavorite) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(item.isPinned ? IOSTheme.starActive : IOSTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(item.isPinned ? "Remove from favorites" : "Add to favorites")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .background(IOSTheme.card)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 204) // Mac collapsedCardHeight
        .background(IOSTheme.neoBase)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipped()
        .onTapGesture(perform: onCopy)
        .contextMenu {
            Button(action: onCopy) {
                Label(menuCapabilities.copyTitle, systemImage: menuCapabilities.copyIcon)
            }
            if menuCapabilities.supportsPlainTextCopy {
                Button(action: onCopyPlainText) {
                    Label("Copy as Plain Text", systemImage: "doc.plaintext")
                }
            }
            if menuCapabilities.supportsAssetActions {
                Divider()
                Button(action: onQuickLook) {
                    Label("Quick Look", systemImage: "eye")
                }
                Button(action: onSave) {
                    Label(menuCapabilities.saveTitle, systemImage: menuCapabilities.saveIcon)
                }
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if item.contentType == .url {
                Divider()
                Button(action: onOpenLink) {
                    Label("Open Link", systemImage: "arrow.up.right")
                }
                Button(action: onOpenLinkPreview) {
                    Label("Open in App Preview", systemImage: "safari")
                }
                Button(action: onShare) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            }
            if item.supportsRichTextEditing {
                Divider()
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Divider()
            Button(action: onToggleFavorite) {
                Label(item.isPinned ? "Remove from Favorites" : "Add to Favorites", systemImage: item.isPinned ? "star.slash" : "star")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let portableColor {
            let color = Color(.sRGB, red: portableColor.red, green: portableColor.green, blue: portableColor.blue, opacity: portableColor.alpha)
            let brightness = (portableColor.red * 0.299) + (portableColor.green * 0.587) + (portableColor.blue * 0.114)
            color.overlay(
                Text(item.contentText ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(brightness > 0.58 ? Color.black.opacity(0.72) : Color.white.opacity(0.94))
                    .shadow(color: brightness > 0.58 ? .white.opacity(0.25) : .black.opacity(0.25), radius: 1)
            )
        } else if item.contentType == .url, let urlText = item.contentText, let url = URL(string: urlText) {
            IOSLinkPreview(url: url)
        } else if item.contentType == .image,
           let data = item.localData ?? ThumbnailCache.shared.data(for: item.id),
           let image = UIImage(data: data) {
            Color(hex: "#F7F7F5")
                .overlay(
                    Image(uiImage: image)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
        } else if item.hasPortableRichText, let attrStr = parseRichText(item) {
            Text(attrStr)
                .lineLimit(5)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(IOSTheme.neoContent)
        } else if let text = item.previewText, !text.isEmpty {
            Text(text)
                .font(.system(size: 9, weight: .regular, design: item.detectedLanguage == nil ? .default : .monospaced))
                .lineLimit(5)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(IOSTheme.textPrimary)
                .padding(8)
                .background(IOSTheme.neoContent)
        } else {
            VStack(spacing: 4) {
                Image(systemName: item.contentType.searchFilterIcon)
                    .font(.system(size: 16))
                Text(item.fileName ?? itemType)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IOSTheme.neoContent)
        }
    }

    private func parseRichText(_ item: ClipboardItem) -> AttributedString? {
        let cacheKey = "\(item.id.uuidString)-\(item.updatedAt?.timeIntervalSinceReferenceDate ?? item.createdAt.timeIntervalSinceReferenceDate)"
        if let cached = RichTextPreviewCache.shared.value(for: cacheKey) {
            return try? AttributedString(cached, including: \.uiKit)
        }
        var nsAttr: NSAttributedString? = nil
        if let rtfd = item.rtfdData {
            nsAttr = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        }
        if nsAttr == nil, let rtf = item.rtfData {
            nsAttr = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        if nsAttr == nil, let html = item.htmlData,
           let preview = safeHTMLPreview(from: html), !preview.isEmpty {
            // Foundation's HTML importer can raise an Objective-C exception
            // (which `try?` cannot catch) for valid but complex web markup.
            // Cards only need a fast preview; retain the original HTML for
            // clipboard restoration and render this safe text projection here.
            return AttributedString(preview)
        }

        guard let validAttr = nsAttr, validAttr.length > 0 else { return nil }

        let mutable = NSMutableAttributedString(attributedString: validAttr)
        if item.detectedLanguage != nil {
            // Xcode puts its editor canvas into the copied RTF as hundreds of
            // per-run background attributes. A card is an app preview, not an
            // embedded Xcode editor: remove that canvas while retaining the
            // semantic formatting and readable syntax colours.
            let range = NSRange(location: 0, length: mutable.length)
            mutable.removeAttribute(.backgroundColor, range: range)
            mutable.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                guard let color = value as? UIColor, color.isTooLightForLightSurface else { return }
                mutable.addAttribute(.foregroundColor, value: UIColor.label, range: subrange)
            }
        }
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            if let font = value as? UIFont {
                let scaled = min(max(font.pointSize * 0.8, 9), 12)
                mutable.addAttribute(.font, value: font.withSize(scaled), range: range)
            } else {
                mutable.addAttribute(.font, value: UIFont.systemFont(ofSize: 10), range: range)
            }
        }

        do {
            RichTextPreviewCache.shared.insert(mutable, for: cacheKey)
            return try AttributedString(mutable, including: \.uiKit)
        } catch {
            return nil
        }
    }

    private func safeHTMLPreview(from data: Data) -> String? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.replacingOccurrences(of: "(?i)<(br|/p|/div|/li|/tr)[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UIColor {
    var isTooLightForLightSurface: Bool {
        guard let components = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components else { return false }
        let red = components[0], green = components.count > 2 ? components[1] : red, blue = components.count > 2 ? components[2] : red
        return (red * 0.2126) + (green * 0.7152) + (blue * 0.0722) > 0.82
    }
}
