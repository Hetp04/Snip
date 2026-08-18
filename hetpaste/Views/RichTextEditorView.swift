import SwiftUI
import AppKit

enum EditorCommand: Equatable {
    case none
    case bold
    case italic
    case underline
    case strikethrough
    case monospace
    case alignLeft
    case alignCenter
    case alignRight
    case increaseFontSize
    case decreaseFontSize
    case changeColor(NSColor)
}

struct RichTextEditorView: NSViewRepresentable {
    let item: ClipboardItem
    @Binding var command: EditorCommand
    @Binding var saveRequested: Bool
    let onSave: (Data?, Data?, Data?, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        
        context.coordinator.textView = textView
        
        var nsAttr: NSAttributedString? = nil
        if let rtfd = item.rtfdData {
            nsAttr = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        } else if let rtf = item.rtfData {
            nsAttr = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } else if let html = item.htmlData {
            nsAttr = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        } else if let language = item.detectedLanguage {
            nsAttr = CodeSyntaxHighlighter.highlightedText(
                item.contentText ?? "",
                language: language,
                fontSize: 13,
                fallbackColor: NSColor.textColor
            )
        } else if let text = item.contentText {
            nsAttr = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor])
        }
        
        if let attr = nsAttr {
            textView.textStorage?.setAttributedString(attr)
        }
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if command != .none {
            context.coordinator.applyCommand(command, to: textView)
            DispatchQueue.main.async {
                self.command = .none
            }
        }
        
        if saveRequested {
            DispatchQueue.main.async {
                context.coordinator.performSave(textView: textView)
                self.saveRequested = false
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditorView
        weak var textView: NSTextView?
        
        init(_ parent: RichTextEditorView) {
            self.parent = parent
        }

        func performSave(textView: NSTextView) {
            let attrString = textView.attributedString()
            let fullRange = NSRange(location: 0, length: attrString.length)
            
            let rtfData = try? attrString.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            
            var rtfdData: Data? = nil
            if attrString.containsAttachments(in: fullRange) {
                rtfdData = try? attrString.rtfd(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            }
            
            let htmlData = try? attrString.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
            let contentText = attrString.string
            
            parent.onSave(rtfData, rtfdData, htmlData, contentText)
        }

        func applyCommand(_ cmd: EditorCommand, to textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return }
            guard let textStorage = textView.textStorage else { return }
            
            switch cmd {
            case .bold:
                textStorage.enumerateAttribute(.font, in: range, options: []) { font, attrRange, _ in
                    if let oldFont = font as? NSFont {
                        let isBold = oldFont.fontDescriptor.symbolicTraits.contains(.bold)
                        let newFont = isBold ? NSFontManager.shared.convert(oldFont, toNotHaveTrait: .boldFontMask) : NSFontManager.shared.convert(oldFont, toHaveTrait: .boldFontMask)
                        textStorage.addAttribute(.font, value: newFont, range: attrRange)
                    }
                }
            case .italic:
                textStorage.enumerateAttribute(.font, in: range, options: []) { font, attrRange, _ in
                    if let oldFont = font as? NSFont {
                        let isItalic = oldFont.fontDescriptor.symbolicTraits.contains(.italic)
                        let newFont = isItalic ? NSFontManager.shared.convert(oldFont, toNotHaveTrait: .italicFontMask) : NSFontManager.shared.convert(oldFont, toHaveTrait: .italicFontMask)
                        textStorage.addAttribute(.font, value: newFont, range: attrRange)
                    }
                }
            case .underline:
                textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { style, attrRange, _ in
                    let isUnderlined = (style as? Int) == NSUnderlineStyle.single.rawValue
                    if isUnderlined {
                        textStorage.removeAttribute(.underlineStyle, range: attrRange)
                    } else {
                        textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: attrRange)
                    }
                }
            case .strikethrough:
                textStorage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { style, attrRange, _ in
                    let isStrikethrough = (style as? Int) == NSUnderlineStyle.single.rawValue
                    if isStrikethrough {
                        textStorage.removeAttribute(.strikethroughStyle, range: attrRange)
                    } else {
                        textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: attrRange)
                    }
                }
            case .monospace:
                textStorage.enumerateAttribute(.font, in: range, options: []) { font, attrRange, _ in
                    if let oldFont = font as? NSFont {
                        let newFont = NSFont.monospacedSystemFont(ofSize: oldFont.pointSize, weight: .regular)
                        textStorage.addAttribute(.font, value: newFont, range: attrRange)
                    }
                }
            case .alignLeft:
                textView.setAlignment(.left, range: range)
            case .alignCenter:
                textView.setAlignment(.center, range: range)
            case .alignRight:
                textView.setAlignment(.right, range: range)
            case .increaseFontSize:
                textStorage.enumerateAttribute(.font, in: range, options: []) { font, attrRange, _ in
                    if let oldFont = font as? NSFont {
                        let newFont = NSFontManager.shared.convert(oldFont, toSize: oldFont.pointSize + 1)
                        textStorage.addAttribute(.font, value: newFont, range: attrRange)
                    }
                }
            case .decreaseFontSize:
                textStorage.enumerateAttribute(.font, in: range, options: []) { font, attrRange, _ in
                    if let oldFont = font as? NSFont {
                        let newFont = NSFontManager.shared.convert(oldFont, toSize: max(8, oldFont.pointSize - 1))
                        textStorage.addAttribute(.font, value: newFont, range: attrRange)
                    }
                }
            case .changeColor(let color):
                textStorage.addAttribute(.foregroundColor, value: color, range: range)
            case .none:
                break
            }
        }
    }
}
