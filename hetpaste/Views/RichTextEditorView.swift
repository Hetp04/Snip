import SwiftUI
import AppKit
import RichTextKit

struct RichTextEditorView: View {
    let item: ClipboardItem
    @Binding var saveRequested: Bool
    let onSave: (Data?, Data?, Data?, String?) -> Void

    @StateObject var context = RichTextContext()
    @State private var text: NSAttributedString
    
    init(item: ClipboardItem, saveRequested: Binding<Bool>, onSave: @escaping (Data?, Data?, Data?, String?) -> Void) {
        self.item = item
        self._saveRequested = saveRequested
        self.onSave = onSave
        
        var initialText = NSAttributedString()
        if let rtfd = item.rtfdData, let parsed = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            initialText = parsed
        } else if let rtf = item.rtfData, let parsed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            initialText = parsed
        } else if let html = item.htmlData, let parsed = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            initialText = parsed
        } else if let contentText = item.contentText {
            initialText = NSAttributedString(string: contentText, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor])
        }
        self._text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            modernToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(Material.ultraThin)
                        .shadow(color: Color.black.opacity(0.05), radius: 3, y: 2)
                )
                .zIndex(1)
            
            Divider()

            RichTextEditor(text: $text, context: context) { textView in
                if let nsTextView = textView as? NSTextView {
                    nsTextView.isRichText = true
                    nsTextView.allowsUndo = true
                    nsTextView.drawsBackground = false
                    nsTextView.isSelectable = true
                    nsTextView.isEditable = true
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color(NSColor.textBackgroundColor))
        }
        .onChange(of: saveRequested) { requested in
            if requested {
                performSave()
            }
        }
    }


    // MARK: - Modern Toolbar
    
    private var modernToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                fontSizeControl
                Divider().frame(height: 20)
                fontStyleControl
                Divider().frame(height: 20)
                alignmentControl
                Divider().frame(height: 20)
                colorControl
            }
            .padding(.horizontal, 4)
        }
    }
    
    private var fontSizeControl: some View {
        HStack(spacing: 4) {
            toolbarActionButton(icon: "minus") { if context.fontSize > 8 { context.fontSize -= 1 } }
            
            Text("\(Int(context.fontSize))")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(width: 26)
                .multilineTextAlignment(.center)
            
            toolbarActionButton(icon: "plus") { if context.fontSize < 144 { context.fontSize += 1 } }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var fontStyleControl: some View {
        HStack(spacing: 4) {
            toolbarToggleButton(icon: "bold", isActive: context.hasStyle(.bold)) { context.toggleStyle(.bold) }
            toolbarToggleButton(icon: "italic", isActive: context.hasStyle(.italic)) { context.toggleStyle(.italic) }
            toolbarToggleButton(icon: "underline", isActive: context.hasStyle(.underlined)) { context.toggleStyle(.underlined) }
            toolbarToggleButton(icon: "strikethrough", isActive: context.hasStyle(.strikethrough)) { context.toggleStyle(.strikethrough) }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var alignmentControl: some View {
        HStack(spacing: 4) {
            toolbarToggleButton(icon: "text.alignleft", isActive: context.textAlignment == .left) { context.textAlignment = .left }
            toolbarToggleButton(icon: "text.aligncenter", isActive: context.textAlignment == .center) { context.textAlignment = .center }
            toolbarToggleButton(icon: "text.alignright", isActive: context.textAlignment == .right) { context.textAlignment = .right }
            toolbarToggleButton(icon: "text.justify", isActive: context.textAlignment == .justified) { context.textAlignment = .justified }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var colorControl: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "character")
                    .font(.system(size: 13, weight: .semibold))
                ColorPicker("", selection: Binding(
                    get: { Color(context.colors[.foreground] ?? NSColor.textColor) },
                    set: { context.setColor(.foreground, to: NSColor($0)) }
                ))
                .labelsHidden()
            }
            
            HStack(spacing: 6) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 13, weight: .semibold))
                ColorPicker("", selection: Binding(
                    get: { Color(context.colors[.background] ?? NSColor.clear) },
                    set: { context.setColor(.background, to: NSColor($0)) }
                ))
                .labelsHidden()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func toolbarToggleButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 26, height: 26)
                .background(isActive ? Color.accentColor : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
    
    private func toolbarActionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 26, height: 26)
                .background(Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func performSave() {
        let fullRange = NSRange(location: 0, length: text.length)
        
        var rtfdData: Data? = nil
        if text.containsAttachments(in: fullRange) {
            rtfdData = text.rtfd(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        }
        
        let rtfData = try? text.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let htmlData = try? text.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        let contentText = text.string
        
        onSave(rtfData, rtfdData, htmlData, contentText)
    }
}
