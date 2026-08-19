import Foundation
#if canImport(AppKit)
import AppKit
#endif
final class FileAccessStore {
    static let shared = FileAccessStore()
    private let fm = FileManager.default
    private init() {}
    private var baseDir: URL {
        let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSup.appendingPathComponent("hetpaste/Bookmarks", isDirectory: true)
    }
    private func bookmarkPath(for id: UUID) -> URL {
        baseDir.appendingPathComponent(id.uuidString).appendingPathExtension("bookmark")
    }
    private func pathFile(for id: UUID) -> URL {
        baseDir.appendingPathComponent(id.uuidString).appendingPathExtension("path")
    }
    func save(url: URL, for id: UUID) throws {
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try url.path.write(to: pathFile(for: id), atomically: true, encoding: .utf8)

        let bookmarkData: Data
        #if os(macOS)
        do {
            bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        #else
        bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        try bookmarkData.write(to: bookmarkPath(for: id), options: .atomic)
    }
    func resolve(for id: UUID) -> URL? {
        let path = bookmarkPath(for: id)
        if let data = try? Data(contentsOf: path) {
            var stale = false
            #if os(macOS)
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale {
                    if let newData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        try? newData.write(to: path, options: .atomic)
                    }
                }
                return url
            }
            #endif
            stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        if let rawPath = try? String(contentsOf: pathFile(for: id), encoding: .utf8) {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed)
            }
        }
        return nil
    }
    #if os(macOS)
    @discardableResult
    func revealInFinder(for id: UUID, fallback: URL?) -> Bool {
        withResolvedURL(for: id, fallback: fallback) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    @discardableResult
    func openFile(for id: UUID, fallback: URL?) -> Bool {
        withResolvedURL(for: id, fallback: fallback) { url in
            NSWorkspace.shared.open(url)
        }
    }
    #endif
    func resolvedURL(for id: UUID, fallback: URL?) -> URL? {
        let url = resolve(for: id) ?? fallback
        guard let url else { return nil }
        guard fm.fileExists(atPath: url.path) else { return nil }
        return url
    }
    private func withResolvedURL(for id: UUID, fallback: URL?, action: (URL) -> Void) -> Bool {
        guard let url = resolvedURL(for: id, fallback: fallback) else { return false }
        var didStart = false
        if url.startAccessingSecurityScopedResource() { didStart = true }
        action(url)
        if didStart {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return true
    }
    func remove(for id: UUID) {
        let path = bookmarkPath(for: id)
        try? fm.removeItem(at: path)
        try? fm.removeItem(at: pathFile(for: id))
    }
}
