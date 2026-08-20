import Foundation
import UniformTypeIdentifiers
import UIKit

/// Shared pasteboard interface for iOS conforming to `ClipboardProviding`.
@MainActor
public final class IOSClipboardProvider: ClipboardProviding {
    public static let shared = IOSClipboardProvider()
    private let pasteboard = UIPasteboard.general

    private init() {}

    public func copyText(_ text: String) {
        pasteboard.string = text
        generateHaptic()
    }

    public func copyRichText(plainText: String?, rtfData: Data?, htmlData: Data?, rtfdData: Data? = nil) {
        var items: [String: Any] = [:]
        if let plainText {
            items[UTType.utf8PlainText.identifier] = plainText
            items[UTType.plainText.identifier] = plainText
        }
        if let rtfData {
            items[UTType.rtf.identifier] = rtfData
        }
        if let htmlData {
            items[UTType.html.identifier] = htmlData
        }
        // RTFD is the only portable representation that can retain AppKit
        // attachments. UIKit does not expose a convenience constant, but the
        // registered UTI is understood by Apple pasteboards.
        if let rtfdData {
            items["com.apple.rtfd"] = rtfdData
        }
        if !items.isEmpty {
            pasteboard.setItems([items])
        } else if let plainText {
            pasteboard.string = plainText
        }
        generateHaptic()
    }

    public func copyImage(data: Data) {
        if let image = UIImage(data: data) {
            pasteboard.image = image
        } else {
            pasteboard.setData(data, forPasteboardType: "public.png")
        }
        generateHaptic()
    }

    public func copyURL(_ url: URL) {
        pasteboard.url = url
        generateHaptic()
    }

    @discardableResult
    public func copyColor(_ value: String?) -> Bool {
        guard let color = PortableClipboardColor.parse(value) else { return false }
        // `color` is UIKit's standard cross-app representation. Keep the
        // source notation as a text fallback for apps that do not accept it.
        let uiColor = UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        // UniformTypeIdentifiers does not currently expose a Swift constant
        // for this long-standing Apple pasteboard type.
        var representations: [String: Any] = ["public.color": uiColor]
        if let value { representations[UTType.utf8PlainText.identifier] = value }
        pasteboard.setItems([representations])
        generateHaptic()
        return true
    }

    public func copyFileData(_ data: Data, fileName: String? = nil) {
        let fileExtension = fileName.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
        let typeIdentifier = UTType(filenameExtension: fileExtension)?.identifier ?? UTType.data.identifier
        pasteboard.setData(data, forPasteboardType: typeIdentifier)
        generateHaptic()
    }

    private func generateHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
