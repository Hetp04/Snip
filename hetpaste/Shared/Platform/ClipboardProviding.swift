import Foundation

/// A platform-agnostic abstraction for interacting with the system clipboard.
public protocol ClipboardProviding: AnyObject {
    /// Copies plain or rich text into the system pasteboard.
    func copyText(_ text: String)

    /// Copies raw image data into the system pasteboard.
    func copyImage(data: Data)

    /// Copies a URL to the system pasteboard.
    func copyURL(_ url: URL)
}
