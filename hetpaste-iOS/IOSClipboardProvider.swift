import Foundation
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

    public func copyRichText(plainText: String?, rtfData: Data?, htmlData: Data?) {
        var items: [String: Any] = [:]
        if let plainText {
            items["public.utf8-plain-text"] = plainText
            items["public.plain-text"] = plainText
        }
        if let rtfData {
            items["public.rtf"] = rtfData
        }
        if let htmlData {
            items["public.html"] = htmlData
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

    private func generateHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
