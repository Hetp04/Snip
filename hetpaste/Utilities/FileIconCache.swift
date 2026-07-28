import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// Cache for file icons and thumbnails - uses QuickLook for content-aware previews
final class FileIconCache {
    static let shared = FileIconCache()
    
    private struct CacheEntry {
        let image: NSImage
        let modificationDate: Date?
    }
    
    private var iconCache: [String: NSImage] = [:]
    private var thumbnailCache: [String: CacheEntry] = [:]
    private let queue = DispatchQueue(label: "com.hetpaste.fileioncache", attributes: .concurrent)
    
    private init() {}
    
    /// Get icon or thumbnail for a file - prioritizes QuickLook thumbnails, falls back to NSWorkspace icons
    func icon(forFileAtPath path: String, size: CGSize = CGSize(width: 64, height: 64), completion: @escaping (NSImage) -> Void) {
        let fileURL = URL(fileURLWithPath: path)
        
        // Get modification date for cache invalidation
        let modDate = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        
        // Check thumbnail cache first
        if let cached = getThumbnailCached(key: path), cached.modificationDate == modDate {
            completion(cached.image)
            return
        }
        
        // Try QuickLook thumbnail generation (for PDFs, images, docs, etc.)
        generateQuickLookThumbnail(for: fileURL, size: size) { [weak self] thumbnail in
            if let thumbnail = thumbnail {
                // Cache and return QuickLook thumbnail
                self?.setThumbnailCache(key: path, image: thumbnail, modDate: modDate)
                completion(thumbnail)
            } else {
                // Fallback to NSWorkspace icon (for code files, etc.)
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = size
                self?.setThumbnailCache(key: path, image: icon, modDate: modDate)
                completion(icon)
            }
        }
    }
    
    /// Synchronous icon fetch - returns immediately with cached or generic, then updates async
    func iconSync(forFileAtPath path: String) -> NSImage {
        // Check cache
        if let cached = getThumbnailCached(key: path) {
            return cached.image
        }
        
        // Return generic icon immediately, fetch real one in background
        let genericIcon = NSWorkspace.shared.icon(forFile: path)
        genericIcon.size = NSSize(width: 64, height: 64)
        
        // Trigger async fetch for next time
        icon(forFileAtPath: path, size: CGSize(width: 64, height: 64)) { _ in }
        
        return genericIcon
    }
    
    /// Generate QuickLook thumbnail (shows PDF first page, image preview, etc.)
    private func generateQuickLookThumbnail(for url: URL, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail  // Real content thumbnail, not just icon
        )
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("QuickLook thumbnail failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    completion(nil)
                } else if let nsImage = thumbnail?.nsImage {
                    completion(nsImage)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    /// Get icon for a file type (extension or UTI) - type icons, not content thumbnails
    func icon(forFileType typeIdentifier: String) -> NSImage {
        if let cached = getIconCached(key: typeIdentifier) {
            return cached
        }
        
        // Try to get icon for the UTType
        let icon: NSImage
        if let utType = UTType(typeIdentifier) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else if let utType = UTType(filenameExtension: typeIdentifier) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            // Fallback to generic document icon
            icon = NSWorkspace.shared.icon(for: .item)
        }
        
        icon.size = NSSize(width: 64, height: 64)
        setIconCache(key: typeIdentifier, value: icon)
        return icon
    }
    
    /// Get icon specifically for folders
    func folderIcon() -> NSImage {
        if let cached = getIconCached(key: "folder") {
            return cached
        }
        
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 64, height: 64)
        setIconCache(key: "folder", value: icon)
        return icon
    }
    
    // MARK: - Thread-Safe Cache Access
    
    private func getIconCached(key: String) -> NSImage? {
        queue.sync {
            iconCache[key]
        }
    }
    
    private func setIconCache(key: String, value: NSImage) {
        queue.async(flags: .barrier) { [weak self] in
            self?.iconCache[key] = value
        }
    }
    
    private func getThumbnailCached(key: String) -> CacheEntry? {
        queue.sync {
            thumbnailCache[key]
        }
    }
    
    private func setThumbnailCache(key: String, image: NSImage, modDate: Date?) {
        queue.async(flags: .barrier) { [weak self] in
            self?.thumbnailCache[key] = CacheEntry(image: image, modificationDate: modDate)
        }
    }
    
    func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            self?.iconCache.removeAll()
            self?.thumbnailCache.removeAll()
        }
    }
}
