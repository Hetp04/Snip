import Foundation

/// The UI never guesses actions from incidental metadata such as OCR text or
/// a filename. This profile describes the portable representation a card can
/// actually restore, keeping context menus consistent on every Apple device.
struct ClipboardContextMenuCapabilities {
    enum SaveDestination { case photos, files }

    let copyTitle: String
    let copyIcon: String
    let supportsPlainTextCopy: Bool
    let supportsAssetActions: Bool
    let saveDestination: SaveDestination?

    var saveTitle: String {
        saveDestination == .photos ? "Save to Photos" : "Save to Files"
    }

    var saveIcon: String {
        saveDestination == .photos ? "photo.badge.arrow.down" : "folder.badge.plus"
    }
}

extension ClipboardItem {
    var supportsRichTextEditing: Bool {
        contentType == .text || contentType == .richText || contentType == .url
    }

    var contextMenuCapabilities: ClipboardContextMenuCapabilities {
        let isColor = PortableClipboardColor.parse(contentText) != nil
        let isRichText = hasPortableRichText
        let isPhotoLibraryAsset = contentType == .image || contentType == .video
            || mimeType?.lowercased().hasPrefix("image/") == true
            || mimeType?.lowercased().hasPrefix("video/") == true
        let isFileAsset = contentType == .file || contentType == .image || contentType == .video

        if isColor {
            return .init(copyTitle: "Copy Color", copyIcon: "paintpalette", supportsPlainTextCopy: false, supportsAssetActions: false, saveDestination: nil)
        }
        if isRichText {
            return .init(copyTitle: "Copy", copyIcon: "doc.on.doc", supportsPlainTextCopy: true, supportsAssetActions: false, saveDestination: nil)
        }
        switch contentType {
        case .text:
            return .init(copyTitle: "Copy", copyIcon: "doc.on.doc", supportsPlainTextCopy: false, supportsAssetActions: false, saveDestination: nil)
        case .url:
            return .init(copyTitle: "Copy Link", copyIcon: "link", supportsPlainTextCopy: false, supportsAssetActions: false, saveDestination: nil)
        case .image:
            return .init(copyTitle: "Copy Image", copyIcon: "photo.on.rectangle", supportsPlainTextCopy: false, supportsAssetActions: true, saveDestination: .photos)
        case .video:
            return .init(copyTitle: "Copy Video", copyIcon: "play.rectangle.on.rectangle", supportsPlainTextCopy: false, supportsAssetActions: true, saveDestination: .photos)
        case .file:
            return .init(copyTitle: "Copy File", copyIcon: "doc.on.doc", supportsPlainTextCopy: false, supportsAssetActions: isFileAsset, saveDestination: isPhotoLibraryAsset ? .photos : .files)
        case .richText:
            // Covered above; retained for exhaustiveness if representations
            // are absent on a legacy record.
            return .init(copyTitle: "Copy", copyIcon: "doc.on.doc", supportsPlainTextCopy: true, supportsAssetActions: false, saveDestination: nil)
        }
    }
}
