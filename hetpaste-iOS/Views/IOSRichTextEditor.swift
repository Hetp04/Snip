import Combine
import SwiftUI
import UIKit

@MainActor
private final class IOSRichTextEditorState: ObservableObject {
    @Published var attributedText: NSAttributedString
    weak var textView: UITextView?

    init(item: ClipboardItem) {
        if let rtfd = item.rtfdData,
           let text = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            attributedText = Self.editorPresentation(text, isCode: item.detectedLanguage != nil)
        } else if let rtf = item.rtfData,
                  let text = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            attributedText = Self.editorPresentation(text, isCode: item.detectedLanguage != nil)
        } else {
            // HTML is retained for clipboard fidelity, but its Foundation
            // importer can throw Objective-C exceptions on complex web markup.
            attributedText = NSAttributedString(string: item.contentText ?? "", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label])
        }
    }

    private static func editorPresentation(_ source: NSAttributedString, isCode: Bool) -> NSAttributedString {
        guard isCode else { return source }
        let mutable = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: mutable.length)
        // This is intentionally presentation-only. The original RTF remains
        // on the card until the user explicitly saves an edit.
        mutable.removeAttribute(.backgroundColor, range: range)
        mutable.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
            guard let color = value as? UIColor, color.isTooLightForLightSurface else { return }
            mutable.addAttribute(.foregroundColor, value: UIColor.label, range: subrange)
        }
        return mutable
    }

    func toggleBold() { mutateSelection { font in font.with(trait: .traitBold) } }
    func toggleItalic() { mutateSelection { font in font.with(trait: .traitItalic) } }
    func toggleUnderline() {
        guard let textView else { return }
        let range = selectedRange(in: textView)
        let current = (textView.attributedText.attribute(.underlineStyle, at: max(range.location, 0), effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        mutable.addAttribute(.underlineStyle, value: current == 0 ? NSUnderlineStyle.single.rawValue : 0, range: range)
        replace(mutable, in: textView, selection: range)
    }
    func changeFontSize(by amount: CGFloat) {
        mutateSelection { font in UIFont(descriptor: font.fontDescriptor, size: min(max(font.pointSize + amount, 9), 72)) }
    }
    func setAlignment(_ alignment: NSTextAlignment) {
        guard let textView else { return }
        let range = selectedRange(in: textView)
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        mutable.addAttribute(.paragraphStyle, value: style, range: range)
        replace(mutable, in: textView, selection: range)
    }
    func setColor(_ color: UIColor, key: NSAttributedString.Key) {
        guard let textView else { return }
        let range = selectedRange(in: textView)
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        mutable.addAttribute(key, value: color, range: range)
        replace(mutable, in: textView, selection: range)
    }

    private func mutateSelection(_ transform: (UIFont) -> UIFont) {
        guard let textView else { return }
        let range = selectedRange(in: textView)
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        mutable.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 17)
            mutable.addAttribute(.font, value: transform(font), range: subrange)
        }
        replace(mutable, in: textView, selection: range)
    }
    private func selectedRange(in textView: UITextView) -> NSRange {
        textView.selectedRange.length > 0 ? textView.selectedRange : NSRange(location: 0, length: textView.attributedText.length)
    }
    private func replace(_ text: NSAttributedString, in textView: UITextView, selection: NSRange) {
        textView.attributedText = text
        textView.selectedRange = selection
        attributedText = text
    }
}

private extension UIFont {
    func with(trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let traits = fontDescriptor.symbolicTraits.symmetricDifference(trait)
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension UIColor {
    var isTooLightForLightSurface: Bool {
        guard let components = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components else { return false }
        let red = components[0], green = components.count > 2 ? components[1] : red, blue = components.count > 2 ? components[2] : red
        return (red * 0.2126) + (green * 0.7152) + (blue * 0.0722) > 0.82
    }
}

private struct IOSRichTextTextView: UIViewRepresentable {
    @ObservedObject var state: IOSRichTextEditorState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.attributedText = state.attributedText
        view.font = .systemFont(ofSize: 17)
        view.backgroundColor = .clear
        view.isEditable = true
        view.isSelectable = true
        view.allowsEditingTextAttributes = true
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        state.textView = view
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if view.attributedText != state.attributedText { view.attributedText = state.attributedText }
        state.textView = view
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        let state: IOSRichTextEditorState
        init(state: IOSRichTextEditorState) { self.state = state }
        func textViewDidChange(_ textView: UITextView) { state.attributedText = textView.attributedText }
    }
}

struct IOSRichTextEditorSheet: View {
    let item: ClipboardItem
    let onSave: (String?, Data?, Data?, Data?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: IOSRichTextEditorState
    @State private var isSaving = false
    @State private var textColor = Color.primary
    @State private var highlightColor = Color.clear

    init(item: ClipboardItem, onSave: @escaping (String?, Data?, Data?, Data?) -> Bool) {
        self.item = item
        self.onSave = onSave
        _state = StateObject(wrappedValue: IOSRichTextEditorState(item: item))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                IOSRichTextTextView(state: state)
            }
            .navigationTitle("Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                }
            }
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { state.changeFontSize(by: -1) } label: { Image(systemName: "textformat.size.smaller") }
                Button { state.changeFontSize(by: 1) } label: { Image(systemName: "textformat.size.larger") }
                Divider().frame(height: 24)
                Button { state.toggleBold() } label: { Image(systemName: "bold") }
                Button { state.toggleItalic() } label: { Image(systemName: "italic") }
                Button { state.toggleUnderline() } label: { Image(systemName: "underline") }
                Divider().frame(height: 24)
                Button { state.setAlignment(.left) } label: { Image(systemName: "text.alignleft") }
                Button { state.setAlignment(.center) } label: { Image(systemName: "text.aligncenter") }
                Button { state.setAlignment(.right) } label: { Image(systemName: "text.alignright") }
                Divider().frame(height: 24)
                ColorPicker("Text", selection: $textColor).labelsHidden()
                    .onChange(of: textColor) { _, value in state.setColor(UIColor(value), key: .foregroundColor) }
                ColorPicker("Highlight", selection: $highlightColor).labelsHidden()
                    .onChange(of: highlightColor) { _, value in state.setColor(UIColor(value), key: .backgroundColor) }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }

    private func save() {
        isSaving = true
        let text = state.attributedText
        let range = NSRange(location: 0, length: text.length)
        let rtf = try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let html = try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        var hasAttachment = false
        text.enumerateAttribute(.attachment, in: range) { value, _, stop in
            hasAttachment = value != nil
            if hasAttachment { stop.pointee = true }
        }
        // Retain embedded images/files from an existing RTFD card rather than
        // silently flattening them on an iPhone edit.
        let rtfd = hasAttachment ? try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) : nil
        let didSave = onSave(text.string, rtf, html, rtfd)
        isSaving = false
        if didSave { dismiss() }
    }
}
