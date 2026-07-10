import Foundation
import Quartz
final class QuickLookPreviewer: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewer()
    private var previewURL: NSURL?
    private var scopedURL: URL?
    private var temporaryURL: URL?
    private var didStartScope = false
    private override init() {}
    func preview(url: URL) {
        stopSecurityScopeIfNeeded()
        removeTemporaryPreviewIfNeeded()
        scopedURL = url
        didStartScope = url.startAccessingSecurityScopedResource()
        previewURL = url as NSURL
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
    func previewImage(data: Data, fileName: String? = nil) {
        stopSecurityScopeIfNeeded()
        removeTemporaryPreviewIfNeeded()
        let name = fileName?.isEmpty == false ? fileName! : "hetpaste-preview.png"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + name)
        do {
            try data.write(to: url, options: .atomic)
            temporaryURL = url
            previewURL = url as NSURL
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        } catch {
            return
        }
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL
    }
    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        stopSecurityScopeIfNeeded()
        removeTemporaryPreviewIfNeeded()
        previewURL = nil
    }
    private func stopSecurityScopeIfNeeded() {
        if didStartScope {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        didStartScope = false
    }
    private func removeTemporaryPreviewIfNeeded() {
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        temporaryURL = nil
    }
}