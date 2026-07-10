import SwiftUI
import AppKit
struct RichTextCodeView: View {
    let item: ClipboardItem
    let lineLimit: Int?
    var fontSize: CGFloat = 10
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
                    .foregroundColor(Theme.codeText)
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
            if let rtf = item.rtfData {
                nsAttr = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            } else if let rtfd = item.rtfdData {
                nsAttr = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            } else if let html = item.htmlData {
                nsAttr = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            }
            guard let validNSAttr = nsAttr else {
                DispatchQueue.main.async { self.attributedText = nil }
                return
            }
            let mutableAttr = NSMutableAttributedString(attributedString: validNSAttr)
            let fullRange = NSRange(location: 0, length: mutableAttr.length)
            let size = fontSize
            mutableAttr.enumerateAttribute(.font, in: fullRange, options: []) { font, range, _ in
                if let oldFont = font as? NSFont {
                    let newFont = NSFont(name: oldFont.fontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                    mutableAttr.addAttribute(.font, value: newFont, range: range)
                } else {
                    mutableAttr.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: range)
                }
            }
            mutableAttr.removeAttribute(.backgroundColor, range: fullRange)
            if let attrStr = try? AttributedString(mutableAttr, including: \.appKit) {
                DispatchQueue.main.async {
                    self.attributedText = attrStr
                }
            } else {
                DispatchQueue.main.async { self.attributedText = nil }
            }
        }
    }
}