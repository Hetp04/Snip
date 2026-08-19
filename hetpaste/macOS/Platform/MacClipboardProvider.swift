import AppKit
import Foundation

/// macOS clipboard implementation conforming to `ClipboardProviding`.
public final class MacClipboardProvider: ClipboardProviding {
    public static let shared = MacClipboardProvider()

    public init() {}

    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func copyImage(data: Data) {
        guard let image = NSImage(data: data) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    public func copyURL(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}
