import SwiftUI
import UIKit

struct IOSClipboardCard: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onToggleFavorite: () -> Void

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
                    iconData: item.appIconData,
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
    }

    @ViewBuilder
    private var preview: some View {
        if item.contentType == .image,
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
        } else if (item.contentType == .richText || item.rtfData != nil || item.htmlData != nil), let attrStr = parseRichText(item) {
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
        var nsAttr: NSAttributedString? = nil
        if let rtfd = item.rtfdData {
            nsAttr = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        }
        if nsAttr == nil, let rtf = item.rtfData {
            nsAttr = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        if nsAttr == nil, let html = item.htmlData {
            nsAttr = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        }

        guard let validAttr = nsAttr, validAttr.length > 0 else { return nil }

        let mutable = NSMutableAttributedString(attributedString: validAttr)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            if let font = value as? UIFont {
                let scaled = min(max(font.pointSize * 0.8, 9), 12)
                mutable.addAttribute(.font, value: font.withSize(scaled), range: range)
            } else {
                mutable.addAttribute(.font, value: UIFont.systemFont(ofSize: 10), range: range)
            }
        }

        do {
            return try AttributedString(mutable, including: \.uiKit)
        } catch {
            return nil
        }
    }
}
