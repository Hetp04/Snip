import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
final class WardrobeViewModel: ObservableObject {
    @Published var items: [WardrobeItem] = []
    @Published var isLoading = false
    @Published var loadError: String?
    
    private let repository = WardrobeRepository()
    
    init() {
        Task {
            await loadItems()
        }
    }
    
    // MARK: - Load
    
    func loadItems() async {
        isLoading = true
        loadError = nil
        
        do {
            let fetchedItems = try await repository.fetchAll()
            items = fetchedItems.map(hydrateFileReference)
        } catch {
            loadError = "Failed to load wardrobe: \(error.localizedDescription)"
            print("❌ Wardrobe load error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Add from External Drop
    
    func addFromDrop(providers: [NSItemProvider], sourceApp: NSRunningApplication? = nil) async {
        // Finder provides one item provider per selected item. Process the full
        // collection; Wardrobe intentionally has no one-file drop limit.
        for provider in providers {
            await addSingleItem(from: provider, source: .external, sourceApp: sourceApp)
        }
    }
    
    private func addSingleItem(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication? = nil) async {
        // Priority order: fileURL first (handles actual files/folders), then content types
        
        // 1. Try file URL - this handles files, folders, archives, anything from Finder
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            await addFileURL(from: provider, source: source, sourceApp: sourceApp)
            return
        }
        
        // 2. Try web URL (not file-based)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            await addURL(from: provider, source: source, sourceApp: sourceApp)
            return
        }
        
        // 3. Try image content (when dropped as image data, not file)
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            await addImage(from: provider, source: source, sourceApp: sourceApp)
            return
        }
        
        // 4. Try RTF (rich text)
        if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
            await addRichText(from: provider, source: source, sourceApp: sourceApp)
            return
        }
        
        // 5. Try plain text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            await addText(from: provider, source: source, sourceApp: sourceApp)
            return
        }
        
        // 6. Fallback: try to handle as generic data
        // This ensures NOTHING is rejected - unrecognized types still get accepted
        await addGenericContent(from: provider, source: source, sourceApp: sourceApp)
    }
    
    private func addFileURL(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication?) async {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                guard error == nil else {
                    continuation.resume()
                    return
                }

                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let fileURL = item as? URL {
                    url = fileURL
                } else if let fileURL = item as? NSURL {
                    url = fileURL as URL
                } else {
                    url = nil
                }

                guard let url else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    do {
                        try await self.handleFileOrFolder(url: url, source: source, sourceApp: sourceApp)
                    } catch {
                        await MainActor.run {
                            self.loadError = "Failed to add file: \(error.localizedDescription)"
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func handleFileOrFolder(url: URL, source: WardrobeSource, sourceApp: NSRunningApplication?) async throws {
        let fileManager = FileManager.default
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .typeIdentifierKey])
        
        let isDirectory = resourceValues.isDirectory ?? false
        let fileName = url.lastPathComponent
        
        // Detect UTType from the file
        let utType: UTType?
        if let typeIdentifier = resourceValues.typeIdentifier {
            utType = UTType(typeIdentifier)
        } else {
            utType = UTType(filenameExtension: url.pathExtension)
        }
        
        if isDirectory {
            // FOLDER - store metadata only, no content upload
            try await handleFolder(url: url, source: source, sourceApp: sourceApp)
        } else {
            // FILE - determine content type and handle accordingly
            try await handleFile(url: url, utType: utType, fileName: fileName, source: source, sourceApp: sourceApp)
        }
    }
    
    private func handleFolder(url: URL, source: WardrobeSource, sourceApp: NSRunningApplication?) async throws {
        let fileManager = FileManager.default
        
        // Count items in folder
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let itemCount = contents.count
        
        // Create a folder reference item - no data upload, just metadata
        var item = WardrobeItem(
            contentType: .file,
            content: "Folder: \(itemCount) items",
            source: source,
            sourceAppName: sourceApp?.localizedName ?? "Finder",
            sourceAppBundleID: sourceApp?.bundleIdentifier,
            fileName: url.lastPathComponent,
            fileSize: nil,
            mimeType: "inode/directory",
            fileExtension: nil
        )
        item.originalFilePath = url.path
        
        try await self.saveItem(item)
    }
    
    private func handleFile(url: URL, utType: UTType?, fileName: String, source: WardrobeSource, sourceApp: NSRunningApplication?) async throws {
        // Read file data
        let fileData = try Data(contentsOf: url)
        let fileSize = Int64(fileData.count)
        let fileExtension = url.pathExtension.lowercased()
        
        // Determine ContentType based on UTType with proper checking
        let contentType: ContentType
        let mimeType: String
        
        if let utType = utType {
            // Check content conformance hierarchy properly
            // Order matters: check more specific types first
            
            if utType.conforms(to: .sourceCode) || 
               utType.conforms(to: .script) ||
               utType.conforms(to: .text) ||
               utType.conforms(to: .plainText) {
                // Text/code files (includes .ts as TypeScript, .js, .py, etc.)
                contentType = .file
                mimeType = utType.preferredMIMEType ?? "text/plain"
            } else if utType.conforms(to: .image) {
                contentType = .image
                mimeType = utType.preferredMIMEType ?? "image/octet-stream"
            } else if utType.conforms(to: .movie) || utType.conforms(to: .video) {
                // Only treat as video if it's actually a video container
                // Check if it has video-specific UTI
                if utType.identifier.contains("video") || 
                   utType.identifier.contains("movie") ||
                   ["mp4", "mov", "avi", "mkv", "m4v", "webm", "mpeg", "mpg"].contains(fileExtension) {
                    contentType = .video
                    mimeType = utType.preferredMIMEType ?? "video/octet-stream"
                } else {
                    // Might be misidentified, treat as file
                    contentType = .file
                    mimeType = utType.preferredMIMEType ?? "application/octet-stream"
                }
            } else if utType.conforms(to: .archive) {
                contentType = .file
                mimeType = utType.preferredMIMEType ?? "application/x-archive"
            } else if utType.conforms(to: .package) {
                contentType = .file
                mimeType = utType.preferredMIMEType ?? "application/octet-stream"
            } else {
                // Everything else
                contentType = .file
                mimeType = utType.preferredMIMEType ?? "application/octet-stream"
            }
        } else {
            // No UTType detected - still accept it as generic file
            contentType = .file
            mimeType = "application/octet-stream"
        }
        
        var item = WardrobeItem(
            contentType: contentType,
            source: source,
            sourceAppName: sourceApp?.localizedName ?? "Unknown",
            sourceAppBundleID: sourceApp?.bundleIdentifier,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType,
            fileExtension: fileExtension.isEmpty ? nil : fileExtension
        )
        item.localData = fileData
        item.originalFilePath = url.path
        
        try await self.saveItem(item)
    }
    
    private func addURL(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication?) async {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                guard error == nil, let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    let item = WardrobeItem(
                        contentType: .url,
                        content: url.absoluteString,
                        source: source,
                        sourceAppName: sourceApp?.localizedName ?? "Unknown",
                        sourceAppBundleID: sourceApp?.bundleIdentifier
                    )
                    
                    do {
                        try await self.saveItem(item)
                    } catch {
                        await MainActor.run {
                            self.loadError = "Failed to add URL: \(error.localizedDescription)"
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func addImage(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication?) async {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                guard let imageData = data, error == nil else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    var item = WardrobeItem(
                        contentType: .image,
                        source: source,
                        sourceAppName: sourceApp?.localizedName ?? "Unknown",
                        sourceAppBundleID: sourceApp?.bundleIdentifier,
                        fileName: "image.png",
                        fileSize: Int64(imageData.count),
                        mimeType: "image/png"
                    )
                    item.localData = imageData
                    
                    do {
                        try await self.saveItem(item)
                    } catch {
                        await MainActor.run {
                            self.loadError = "Failed to add image: \(error.localizedDescription)"
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func addText(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication?) async {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                guard error == nil else {
                    continuation.resume()
                    return
                }
                
                let text: String?
                if let data = item as? Data {
                    text = String(data: data, encoding: .utf8)
                } else if let string = item as? String {
                    text = string
                } else if let string = item as? NSString {
                    text = string as String
                } else {
                    text = nil
                }
                
                guard let text = text else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    let item = WardrobeItem(
                        contentType: .text,
                        content: text,
                        source: source,
                        sourceAppName: sourceApp?.localizedName ?? "Unknown",
                        sourceAppBundleID: sourceApp?.bundleIdentifier
                    )
                    
                    do {
                        try await self.saveItem(item)
                    } catch {
                        await MainActor.run {
                            self.loadError = "Failed to add text: \(error.localizedDescription)"
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func addRichText(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication?) async {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.rtf.identifier) { [weak self] data, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                guard let rtfData = data, error == nil else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    // Extract plain text from RTF for storage
                    let plainText: String?
                    if let attributedString = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                        plainText = attributedString.string
                    } else {
                        plainText = nil
                    }
                    
                    let item = WardrobeItem(
                        contentType: .richText,
                        content: plainText,
                        source: source,
                        sourceAppName: sourceApp?.localizedName ?? "Unknown",
                        sourceAppBundleID: sourceApp?.bundleIdentifier
                    )
                    
                    do {
                        try await self.saveItem(item)
                    } catch {
                        await MainActor.run {
                            self.loadError = "Failed to add rich text: \(error.localizedDescription)"
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Generic Fallback Handler
    
    private func addGenericContent(from provider: NSItemProvider, source: WardrobeSource, sourceApp: NSRunningApplication?) async {
        // Last resort: accept anything we haven't specifically handled
        // This ensures NOTHING is rejected - the promise of "drag anything"
        
        // Try to get any registered type identifier
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first else {
            await MainActor.run {
                self.loadError = "Unable to determine content type"
            }
            return
        }
        
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                guard let contentData = data, error == nil else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    // Create generic file item with whatever we got
                    let utType = UTType(typeIdentifier)
                    let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"
                    
                    // Try to infer a reasonable filename
                    let fileName: String
                    if let ext = utType?.preferredFilenameExtension {
                        fileName = "file.\(ext)"
                    } else {
                        fileName = "file"
                    }
                    
                    var item = WardrobeItem(
                        contentType: .file,
                        source: source,
                        sourceAppName: sourceApp?.localizedName ?? "Unknown",
                        sourceAppBundleID: sourceApp?.bundleIdentifier,
                        fileName: fileName,
                        fileSize: Int64(contentData.count),
                        mimeType: mimeType
                    )
                    item.localData = contentData
                    
                    do {
                        try await self.saveItem(item)
                    } catch {
                        await MainActor.run {
                            self.loadError = "Failed to add content: \(error.localizedDescription)"
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Add from Internal ClipboardItem
    
    func addFromClipboardItem(_ clipboardItem: ClipboardItem) async {
        var item = WardrobeItem(
            contentType: clipboardItem.contentType,
            content: clipboardItem.contentText,
            source: .internalReference,
            sourceSnippetID: clipboardItem.id,
            fileName: clipboardItem.fileName,
            fileSize: clipboardItem.fileSize,
            mimeType: clipboardItem.mimeType
        )

        // Internal drags get a new Wardrobe ID, so copy the source file reference
        // to that new item instead of relying on the ClipboardItem's bookmark.
        if let originalURL = clipboardItem.revealableFileURL {
            item.originalFilePath = originalURL.path
        }
        
        // If it has local data, use it
        if let localData = clipboardItem.localData {
            item.localData = localData
        } else if let storagePath = clipboardItem.storagePath, let bucket = clipboardItem.bucket {
            // Download from clipboard storage
            do {
                let clipboardRepo = ClipboardRepository()
                if let data = try await clipboardRepo.downloadData(for: clipboardItem) {
                    item.localData = data
                }
            } catch {
                loadError = "Failed to download data: \(error.localizedDescription)"
            }
        }
        
        do {
            try await saveItem(item)
        } catch {
            loadError = "Failed to add to wardrobe: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Save & Delete

    private func hydrateFileReference(_ item: WardrobeItem) -> WardrobeItem {
        var hydratedItem = item
        if let wardrobeURL = FileAccessStore.shared.resolvedURL(for: item.id, fallback: nil) {
            hydratedItem.originalFilePath = wardrobeURL.path
            return hydratedItem
        }

        // Migrate Wardrobe cards created from clipboard history before they had
        // their own bookmark. The source snippet ID points at the original one.
        if let sourceID = item.sourceSnippetID,
           let sourceURL = FileAccessStore.shared.resolvedURL(for: sourceID, fallback: nil) {
            if (try? FileAccessStore.shared.save(url: sourceURL, for: item.id)) != nil {
                hydratedItem.originalFilePath = sourceURL.path
            }
        }
        return hydratedItem
    }
    
    private func saveItem(_ item: WardrobeItem) async throws {
        var savedLocalReference = false
        if let originalFilePath = item.originalFilePath {
            // A Wardrobe file card is a reference. Do not create it if its local
            // path and bookmark cannot be made durable across app restarts.
            try FileAccessStore.shared.save(
                url: URL(fileURLWithPath: originalFilePath),
                for: item.id
            )
            savedLocalReference = true
        }

        do {
            let saved = try await repository.save(item)
            items.insert(saved, at: 0)
        } catch {
            if savedLocalReference {
                FileAccessStore.shared.remove(for: item.id)
            }
            throw error
        }
    }
    
    func deleteItem(_ item: WardrobeItem) {
        Task {
            do {
                try await repository.delete(id: item.id)
                items.removeAll { $0.id == item.id }
                FileAccessStore.shared.remove(for: item.id)
            } catch {
                loadError = "Failed to delete: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Finder

    func revealInFinder(_ item: WardrobeItem) -> (didReveal: Bool, message: String) {
        let fallbackURL = item.originalFilePath.map(URL.init(fileURLWithPath:))
        let didReveal = FileAccessStore.shared.revealInFinder(for: item.id, fallback: fallbackURL)
        if didReveal {
            return (true, "Shown in Finder")
        }
        return (false, "Can't find this file — it may have been moved or deleted")
    }
    
    // MARK: - Copy to Clipboard
    
    func copyToClipboard(_ item: WardrobeItem) async -> (didCopy: Bool, message: String) {
        do {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            
            switch item.contentType {
            case .text, .richText:
                guard let text = item.content else {
                    return (false, "No text content")
                }
                pasteboard.setString(text, forType: .string)
                return (true, "Copied")
                
            case .url:
                guard let urlString = item.content, let url = URL(string: urlString) else {
                    return (false, "Invalid URL")
                }
                pasteboard.setString(url.absoluteString, forType: .string)
                return (true, "URL copied")
                
            case .image, .video, .file:
                // Download if needed
                var data = item.localData
                if data == nil, item.storagePath != nil {
                    data = try await repository.downloadData(for: item)
                }
                
                guard let data = data else {
                    return (false, "No file data")
                }
                
                if item.contentType == .image {
                    if let image = NSImage(data: data) {
                        pasteboard.clearContents()
                        pasteboard.writeObjects([image])
                        return (true, "Image copied")
                    }
                }
                
                // For files, write to temp and copy file URL
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.fileName ?? "file")
                try data.write(to: tempURL)
                pasteboard.clearContents()
                pasteboard.writeObjects([tempURL as NSURL])
                return (true, "File copied")
            }
        } catch {
            return (false, "Copy failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load Data
    
    func loadLocalDataIfNeeded(for item: WardrobeItem) {
        guard item.localData == nil, item.storagePath != nil else { return }
        
        Task {
            do {
                let data = try await repository.downloadData(for: item)
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].localData = data
                }
            } catch {
                print("Failed to load data for wardrobe item: \(error)")
            }
        }
    }
}

// MARK: - URL Extensions

extension URL {
    var isImage: Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        return imageExtensions.contains(pathExtension.lowercased())
    }
    
    var isVideo: Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "webm"]
        return videoExtensions.contains(pathExtension.lowercased())
    }
    
    func mimeType() -> String? {
        guard let uti = UTType(filenameExtension: pathExtension) else { return nil }
        return uti.preferredMIMEType
    }
}
