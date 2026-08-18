import SwiftUI
import AppKit

/// Full-size popover that lets the user read, edit, and copy a text or rich-text
/// clipboard card without losing any original formatting.
struct ExpandedTextSnippetView: View {
    let item: ClipboardItem
    var onSave: ((UUID, String?, Data?, Data?, Data?) -> Void)?
    
    @State private var isCopied = false
    @State private var isButtonHovered = false
    
    @State private var command: EditorCommand = .none
    @State private var saveRequested = false
    @State private var isSaving = false

    private var contentLabel: String {
        if item.rtfdData != nil  { return "Rich Text (RTFD)" }
        if item.rtfData  != nil  { return "Rich Text (RTF)"  }
        if item.htmlData != nil  { return "HTML"             }
        if let lang = item.detectedLanguage { return lang.capitalized }
        return item.contentType == .richText ? "Rich Text" : "Plain Text"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            toolbar
            Divider()
            content
        }
        .background(Color.white)
        .frame(minWidth: 460, idealWidth: 560, maxWidth: 900,
               minHeight: 320, idealHeight: 450, maxHeight: 800)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceAppName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text(contentLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isCopied {
                Text("Copied!")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Button(action: copyToClipboard) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isCopied ? Theme.accent : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isButtonHovered
                                  ? Color.black.opacity(0.07)
                                  : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isButtonHovered = hovering }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        HStack(spacing: 4) {
            Group {
                toolbarButton(icon: "bold", action: { command = .bold })
                toolbarButton(icon: "italic", action: { command = .italic })
                toolbarButton(icon: "underline", action: { command = .underline })
                toolbarButton(icon: "strikethrough", action: { command = .strikethrough })
                toolbarButton(icon: "textformat.123", action: { command = .monospace })
            }
            Divider().frame(height: 16)
            Group {
                toolbarButton(icon: "text.alignleft", action: { command = .alignLeft })
                toolbarButton(icon: "text.aligncenter", action: { command = .alignCenter })
                toolbarButton(icon: "text.alignright", action: { command = .alignRight })
            }
            Divider().frame(height: 16)
            Group {
                toolbarButton(icon: "textformat.size.larger", action: { command = .increaseFontSize })
                toolbarButton(icon: "textformat.size.smaller", action: { command = .decreaseFontSize })
                
                ColorPicker("", selection: Binding(get: { Color.black }, set: { newColor in
                    command = .changeColor(NSColor(newColor))
                }))
                .labelsHidden()
                .frame(width: 24, height: 24)
            }
            
            Spacer()
            
            Button(action: {
                isSaving = true
                saveRequested = true
            }) {
                HStack(spacing: 4) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Content
    private var content: some View {
        RichTextEditorView(item: item, command: $command, saveRequested: $saveRequested, onSave: handleSave)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(Color.white)
    }

    private func handleSave(rtfData: Data?, rtfdData: Data?, htmlData: Data?, contentText: String?) {
        onSave?(item.id, contentText, rtfData, htmlData, rtfdData)
        isSaving = false
    }

    // MARK: - Clipboard Action
    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()

        var wrote = false

        if let rtfd = item.rtfdData { pb.setData(rtfd, forType: .rtfd); wrote = true }
        if let rtf = item.rtfData { pb.setData(rtf, forType: .rtf); wrote = true }
        if let html = item.htmlData { pb.setData(html, forType: .html); wrote = true }
        if let text = item.contentText { pb.setString(text, forType: .string); wrote = true }

        guard wrote else { return }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }
}
