import AppKit
import Foundation

/// A small, persistent visual preview for image cards. It is intentionally
/// separate from `AssetCache`: clearing full offline originals must not turn
/// the library grid into a set of expensive CloudKit downloads.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let maximumDimension: CGFloat = 640
    private let maximumBytes: Int64 = 100 * 1024 * 1024
    private let directory: URL

    private init(fileManager: FileManager = .default) {
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
        directory = support.appendingPathComponent("hetpaste/thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(for id: UUID) -> Data? {
        let url = url(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, for id: UUID) {
        guard !data.isEmpty else { return }
        try? data.write(to: url(for: id), options: [.atomic, .completeFileProtection])
        trimIfNeeded()
    }

    func createAndStore(from sourceData: Data, for id: UUID) {
        guard let image = NSImage(data: sourceData), image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let targetSize = NSSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else { return }
        store(jpeg, for: id)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("jpg")
    }

    private func trimIfNeeded() {
        let values: [(URL, Int64, Date)] = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]))?.compactMap { url in
            let resource = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = resource?.fileSize else { return nil }
            return (url, Int64(size), resource?.contentModificationDate ?? .distantPast)
        } ?? []
        var remaining = values.reduce(Int64(0)) { $0 + $1.1 }
        for (url, size, _) in values.sorted(by: { $0.2 < $1.2 }) where remaining > maximumBytes {
            try? FileManager.default.removeItem(at: url)
            remaining -= size
        }
    }
}
