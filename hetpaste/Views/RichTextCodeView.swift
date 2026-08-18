import SwiftUI
import AppKit
struct RichTextCodeView: View {
    let item: ClipboardItem
    let lineLimit: Int?
    var fontSize: CGFloat = 10
    /// The card preview has a light surface, so its fallback must be dark.
    var textColor: NSColor = NSColor(calibratedWhite: 0.22, alpha: 1)
    @State private var attributedText: AttributedString? = nil
    var body: some View {
        Group {
            if let attributedText = attributedText {
                Text(attributedText)
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
            } else {
                Text(item.contentText ?? "")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(Color(nsColor: textColor))
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
            }
        }
        .onAppear {
            loadRichText()
        }
        .onChange(of: item.id) { _ in
            loadRichText()
        }
    }
    private func loadRichText() {
        DispatchQueue.global(qos: .userInitiated).async {
            var nsAttr: NSAttributedString? = nil
            if let rtfd = item.rtfdData {
                nsAttr = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            } else if let rtf = item.rtfData {
                nsAttr = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            } else if let html = item.htmlData {
                nsAttr = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            }
            // Xcode and several other editors copy source as UTF-8 plain text,
            // without an RTF or HTML representation. Give recognised code a
            // syntax-coloured display in that case instead of falling back to
            // a single-colour Text view.
            if nsAttr == nil, let language = item.detectedLanguage {
                nsAttr = CodeSyntaxHighlighter.highlightedText(
                    item.contentText ?? "",
                    language: language,
                    fontSize: fontSize,
                    fallbackColor: textColor
                )
            }
            guard let validNSAttr = nsAttr else {
                DispatchQueue.main.async { self.attributedText = nil }
                return
            }
            let mutableAttr = NSMutableAttributedString(attributedString: validNSAttr)
            let fullRange = NSRange(location: 0, length: mutableAttr.length)
            // A clipboard item may carry the source app's 18–36pt font. Keeping
            // that exact size makes a compact card look broken. Keep meaningful
            // emphasis (bold/italic), colours, and line breaks, but render every
            // run at the card's controlled preview size.
            let size = fontSize
            mutableAttr.enumerateAttribute(.font, in: fullRange, options: []) { font, range, _ in
                let oldFont = font as? NSFont
                let traits = oldFont?.fontDescriptor.symbolicTraits ?? []
                let weight: NSFont.Weight = traits.contains(.bold) ? .semibold : .regular
                var normalized = NSFont.systemFont(ofSize: size, weight: weight)
                if traits.contains(.italic), let italicDescriptor = normalized.fontDescriptor.withSymbolicTraits(.italic) {
                    normalized = NSFont(descriptor: italicDescriptor, size: size) ?? normalized
                }
                mutableAttr.addAttribute(.font, value: normalized, range: range)
            }
            mutableAttr.removeAttribute(.backgroundColor, range: fullRange)
            // Xcode and web pages may include light syntax colours intended for
            // a dark editor. Preserve each colour where it is readable, and only
            // correct colours that would disappear on this light card.
            mutableAttr.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { color, range, _ in
                guard let color = color as? NSColor else { return }
                mutableAttr.addAttribute(.foregroundColor, value: self.readableCodeColor(color), range: range)
            }
            if let attrStr = try? AttributedString(mutableAttr, including: \.appKit) {
                DispatchQueue.main.async {
                    self.attributedText = attrStr
                }
            } else {
                DispatchQueue.main.async { self.attributedText = nil }
            }
        }
    }

    private func readableCodeColor(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        // The preview background is almost white; preserve colours with at
        // least 3:1 contrast and darken only the ones that would disappear.
        guard 1.05 / (luminance + 0.05) < 3 else { return rgb }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        if saturation < 0.12 {
            return textColor
        }
        return NSColor(
            calibratedHue: hue,
            saturation: max(saturation, 0.45),
            brightness: min(brightness, 0.58),
            alpha: max(rgb.alphaComponent, 0.88)
        )
    }
}
