import Foundation
import AppKit
final class IconCache {
    static let shared = IconCache()
    private let mem = NSCache<NSString, NSImage>()
    private let fm = FileManager.default
    private init() {}
    private func appSupportDir(subfolder: String) -> URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("hetpaste/")
            .appendingPathComponent(subfolder, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    private func appIconURL(for bundleID: String) -> URL {
        appSupportDir(subfolder: "AppIcons").appendingPathComponent(bundleID).appendingPathExtension("png")
    }
    private func faviconURL(for host: String) -> URL {
        appSupportDir(subfolder: "Favicons").appendingPathComponent(host).appendingPathExtension("png")
    }
    private func fileIconURL(forItemId id: UUID) -> URL {
        appSupportDir(subfolder: "FileIcons").appendingPathComponent(id.uuidString).appendingPathExtension("png")
    }
    private func pngData(of image: NSImage, targetSize: CGSize? = nil) -> Data? {
        let finalImage: NSImage
        if let size = targetSize { finalImage = image.resized(to: size) } else { finalImage = image }
        guard let tiff = finalImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data
    }
    func cachedAppIcon(bundleID: String) -> NSImage? {
        if let memHit = mem.object(forKey: bundleID as NSString) { return memHit }
        let url = appIconURL(for: bundleID)
        if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            mem.setObject(img, forKey: bundleID as NSString)
            return img
        }
        return nil
    }

    /// Warm the memory cache from the on-disk icon cache before a scrolling
    /// view needs the images. This deliberately avoids resolving new icons or
    /// drawing images here, so it is safe to run away from the UI thread.
    func prewarmCachedAppIcons(bundleIDs: [String]) {
        let uniqueBundleIDs = Array(Set(bundleIDs))
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for bundleID in uniqueBundleIDs {
                _ = self.cachedAppIcon(bundleID: bundleID)
            }
        }
    }
    func saveAppIcon(_ image: NSImage, bundleID: String) {
        guard let data = pngData(of: image, targetSize: CGSize(width: 64, height: 64)) else { return }
        let url = appIconURL(for: bundleID)
        try? data.write(to: url, options: .atomic)
        mem.setObject(NSImage(data: data) ?? image, forKey: bundleID as NSString)
    }
    func resolveAppIcon(bundleID: String) -> NSImage? {
        if let hit = cachedAppIcon(bundleID: bundleID) { return hit }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 64, height: 64)
            saveAppIcon(icon, bundleID: bundleID)
            return icon
        }
        return nil
    }
    func prime(bundleID: String?, runningIcon: NSImage?) {
        guard let bid = bundleID, let image = runningIcon else { return }
        if cachedAppIcon(bundleID: bid) == nil { saveAppIcon(image, bundleID: bid) }
    }
    func cachedFavicon(host: String) -> NSImage? {
        if let memHit = mem.object(forKey: ("fav_"+host) as NSString) { return memHit }
        let url = faviconURL(for: host)
        if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            mem.setObject(img, forKey: ("fav_"+host) as NSString)
            return img
        }
        return nil
    }
    func fetchFavicon(forHost host: String, completion: @escaping (NSImage?) -> Void) {
        if let hit = cachedFavicon(host: host) { completion(hit); return }
        let candidates = [
            URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)"),
            URL(string: "https://\(host)/favicon.ico")
        ].compactMap { $0 }
        func attempt(_ idx: Int) {
            guard idx < candidates.count else { completion(nil); return }
            let url = candidates[idx]
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data, let img = NSImage(data: data) {
                    let path = self.faviconURL(for: host)
                    try? data.write(to: path, options: .atomic)
                    self.mem.setObject(img, forKey: ("fav_"+host) as NSString)
                    DispatchQueue.main.async { completion(img) }
                } else {
                    attempt(idx+1)
                }
            }
            task.resume()
        }
        attempt(0)
    }
    func fileIcon(for url: URL) -> NSImage {
        let key = ("file_" + url.path) as NSString
        if let hit = mem.object(forKey: key) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 28, height: 28)
        mem.setObject(icon, forKey: key)
        return icon
    }
    func saveFileIcon(_ image: NSImage, forItemId id: UUID) {
        guard let data = pngData(of: image, targetSize: CGSize(width: 64, height: 64)) else { return }
        let url = fileIconURL(forItemId: id)
        try? data.write(to: url, options: .atomic)
        if let img = NSImage(data: data) {
            mem.setObject(img, forKey: ("fileItem_"+id.uuidString) as NSString)
        }
    }
    func cachedFileIcon(forItemId id: UUID) -> NSImage? {
        let memKey = ("fileItem_"+id.uuidString) as NSString
        if let hit = mem.object(forKey: memKey) { return hit }
        let url = fileIconURL(forItemId: id)
        if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            mem.setObject(img, forKey: memKey)
            return img
        }
        return nil
    }
}
final class LinkPreviewCache {
    static let shared = LinkPreviewCache()
    
    final class CachedMetadata: NSObject {
        let title: String?
        let image: NSImage?
        let icon: NSImage?
        init(title: String?, image: NSImage?, icon: NSImage?) {
            self.title = title
            self.image = image
            self.icon = icon
        }
    }
    
    private let mem = NSCache<NSString, CachedMetadata>()
    private let fm = FileManager.default
    
    private init() {
        mem.countLimit = 300
    }
    
    private func linkPreviewDir() -> URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("hetpaste/LinkPreviews", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private func sanitizeKey(_ urlString: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return urlString.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }
    
    private func imageURL(for key: String) -> URL {
        linkPreviewDir().appendingPathComponent(sanitizeKey(key)).appendingPathExtension("png")
    }
    
    private func titleURL(for key: String) -> URL {
        linkPreviewDir().appendingPathComponent(sanitizeKey(key)).appendingPathExtension("txt")
    }
    
    func cachedMetadata(for url: URL) -> CachedMetadata? {
        let key = url.absoluteString as NSString
        if let hit = mem.object(forKey: key) {
            return hit
        }
        let imgPath = imageURL(for: url.absoluteString)
        let txtPath = titleURL(for: url.absoluteString)
        var diskImage: NSImage?
        var diskTitle: String?
        if let imgData = try? Data(contentsOf: imgPath), let img = NSImage(data: imgData) {
            diskImage = img
        }
        if let txtData = try? Data(contentsOf: txtPath), let txt = String(data: txtData, encoding: .utf8) {
            diskTitle = txt
        }
        if diskImage != nil || diskTitle != nil {
            let hit = CachedMetadata(title: diskTitle, image: diskImage, icon: nil)
            mem.setObject(hit, forKey: key)
            return hit
        }
        return nil
    }
    
    func save(title: String?, image: NSImage?, icon: NSImage?, for url: URL) {
        let key = url.absoluteString as NSString
        let metadata = CachedMetadata(title: title, image: image, icon: icon)
        mem.setObject(metadata, forKey: key)
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let imgPath = self.imageURL(for: url.absoluteString)
            let txtPath = self.titleURL(for: url.absoluteString)
            if let image,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: imgPath, options: .atomic)
            }
            if let title, let txtData = title.data(using: .utf8) {
                try? txtData.write(to: txtPath, options: .atomic)
            }
        }
    }
}
private extension NSImage {
    func resized(to size: CGSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
        img.unlockFocus()
        return img
    }
}
