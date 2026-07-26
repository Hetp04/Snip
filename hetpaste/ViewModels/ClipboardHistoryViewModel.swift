import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
extension UTType {
    static let hetpasteFolderItemIDs = UTType(exportedAs: "com.hetpaste.folder-item-ids")
}
struct ClipboardRestoreResult {
    let didCopy: Bool
    let message: String
}
@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    var trashedItems: [ClipboardItem] { items.filter { $0.isDeleted } }
    var activeItems: [ClipboardItem] { items.filter { !$0.isDeleted } }
    @Published private(set) var folders: [ClipboardFolder] = []
    @Published private(set) var chains: [Chain] = []
    @Published private(set) var chainItems: [UUID: [ChainItem]] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published var loadError: String?
    @Published var focusedItemID: UUID?
    @Published var expandedItemID: UUID?
    @Published var psychoCopyManager: PsychoCopyManager
    private let service = ClipboardService()
    private let repository = ClipboardRepository()
    private var pendingFolderIDs: Set<UUID> = []
    init() {
        self.psychoCopyManager = PsychoCopyManager()
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        psychoCopyManager.onGlobalPasteRequested = { [weak self] in
            guard let self = self else { return }
            self.performSequentialPaste()
        }
        psychoCopyManager.onGlobalReversePasteRequested = { [weak self] in
            guard let self = self else { return }
            self.performReverseSequentialPaste()
        }
        NotificationCenter.default.addObserver(
            forName: PsychoCopyManager.modeChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.service.captureRawTypes = self.psychoCopyManager.isMultiCopyModeActive
        }
        service.onNewItem = { [weak self] item in
            Task { @MainActor in self?.handleNewItem(item) }
        }
        service.start()
        Task { await loadHistory() }
    }
    func loadHistory() async {
        isLoading = true
        loadError = nil
        do {
            async let loadedItems = repository.fetchAll()
            async let loadedFolders = repository.fetchFolders()
            async let loadedChainsTask: () = loadChains()
            var loaded = try await loadedItems
            for i in 0..<loaded.count {
                if loaded[i].contentType == .file || loaded[i].contentType == .image || loaded[i].contentType == .video {
                    if loaded[i].originalFileURL == nil, let url = FileAccessStore.shared.resolve(for: loaded[i].id) {
                        loaded[i].originalFileURL = url
                    }
                    if let url = loaded[i].originalFileURL, IconCache.shared.cachedFileIcon(forItemId: loaded[i].id) == nil {
                        let icon = IconCache.shared.fileIcon(for: url)
                        IconCache.shared.saveFileIcon(icon, forItemId: loaded[i].id)
                    }
                }
            }
            items = loaded
            let remoteFolders = try await loadedFolders
            folders = mergeFolders(remoteFolders)
            _ = await loadedChainsTask
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
    
    private func loadChains() async {
        do {
            let fetchedChains = try await repository.fetchChains()
            var itemsDict: [UUID: [ChainItem]] = [:]
            for chain in fetchedChains {
                let items = try await repository.fetchChainItems(chainID: chain.id)
                itemsDict[chain.id] = items
            }
            self.chains = fetchedChains
            self.chainItems = itemsDict
        } catch {
            print("Failed to load chains: \(error)")
        }
    }
    private func handleNewItem(_ item: ClipboardItem) {
        if let first = items.first,
           first.contentType == item.contentType,
           first.contentText == item.contentText,
           item.localData == nil {
            return
        }
        psychoCopyManager.handleClipboardChange(item)
        items.insert(item, at: 0)
        Task { await sync(item) }
        // Run OCR in background immediately after image capture
        if item.contentType == .image, item.localData != nil {
            updateItem(id: item.id) { $0.ocrStatus = .pending }
            triggerOCRInBackground(for: item.id)
        }
    }
    /// Public: trigger OCR for an existing item (e.g. opened in viewer before OCR ran)
    func triggerOCRIfNeeded(for item: ClipboardItem) {
        guard item.contentType == .image,
              item.ocrStatus != .done,
              item.localData != nil
        else { return }
        updateItem(id: item.id) { $0.ocrStatus = .pending }
        triggerOCRInBackground(for: item.id)
    }
    private func triggerOCRInBackground(for itemID: UUID) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let data: Data? = await MainActor.run {
                self.items.first(where: { $0.id == itemID })?.localData
            }
            guard let data, let image = NSImage(data: data) else {
                await MainActor.run { self.updateItem(id: itemID) { $0.ocrStatus = .failed } }
                return
            }
            do {
                let boxes = try await OCRService.shared.recognizeText(in: image)
                await MainActor.run {
                    self.updateItem(id: itemID) {
                        if boxes.isEmpty {
                            $0.ocrStatus = .none
                        } else {
                            $0.ocrText   = boxes.map(\.text).joined(separator: " ")
                            $0.ocrStatus = .done
                        }
                    }
                }
            } catch {
                await MainActor.run { self.updateItem(id: itemID) { $0.ocrStatus = .failed } }
            }
        }
    }
    private func sync(_ item: ClipboardItem) async {
        do {
            let saved = try await repository.save(item)
            updateItem(id: item.id) {
                $0.syncStatus = .synced
                $0.storagePath = saved.storagePath
            }
        } catch {
            updateItem(id: item.id) { $0.syncStatus = .failed }
        }
    }
    func retrySync(_ item: ClipboardItem) {
        updateItem(id: item.id) { $0.syncStatus = .pending }
        if let fresh = items.first(where: { $0.id == item.id }) {
            Task { await sync(fresh) }
        }
    }
    func loadLocalDataIfNeeded(for item: ClipboardItem) {
        guard item.localData == nil, item.bucket != nil, item.storagePath != nil else { return }
        Task {
            if let data = try? await repository.downloadData(for: item) {
                updateItem(id: item.id) { $0.localData = data }
            }
        }
    }
    func toggleFavorite(_ item: ClipboardItem) {
        let newValue = !item.isPinned
        updateItem(id: item.id) { $0.isPinned = newValue }
        Task {
            do {
                try await repository.setFavorite(id: item.id, isFavorite: newValue)
            } catch {
                updateItem(id: item.id) { $0.isPinned = !newValue }
            }
        }
    }
    func moveToTrash(_ item: ClipboardItem) {
        updateItem(id: item.id) {
            $0.isDeleted = true
            $0.deletedAt = Date()
        }
    }
    func restoreFromTrash(_ item: ClipboardItem) {
        updateItem(id: item.id) {
            $0.isDeleted = false
            $0.deletedAt = nil
        }
    }
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        Task {
            do {
                try await repository.delete(id: item.id)
            } catch {
                print("Failed to delete item: \(error)")
            }
        }
    }
    func emptyTrash() {
        let toDelete = trashedItems
        items.removeAll { $0.isDeleted }
        Task {
            for item in toDelete {
                try? await repository.delete(id: item.id)
            }
        }
    }
    func itemCount(in folder: ClipboardFolder) -> Int {
        items.filter { $0.folderID == folder.id }.count
    }
    @discardableResult
    func createFolder(named name: String = "Untitled Folder") -> ClipboardFolder {
        let folder = ClipboardFolder(id: UUID(), name: name, createdAt: Date(), updatedAt: Date())
        pendingFolderIDs.insert(folder.id)
        folders.append(folder)
        Task {
            do {
                let currentName = folders.first(where: { $0.id == folder.id })?.name ?? folder.name
                try await repository.createFolder(id: folder.id, name: currentName)
                pendingFolderIDs.remove(folder.id)
                let remoteFolders = try await repository.fetchFolders()
                folders = mergeFolders(remoteFolders)
                loadError = nil
            } catch {
                pendingFolderIDs.remove(folder.id)
                folders.removeAll { $0.id == folder.id }
                loadError = folderErrorMessage(for: error, fallback: "Couldn't create folder")
            }
        }
        return folder
    }
    func renameFolder(_ folder: ClipboardFolder, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? "Untitled Folder" : trimmed
        let previousFolder = folder
        updateFolder(id: folder.id) {
            $0.name = newName
            $0.updatedAt = Date()
        }
        Task {
            do {
                try await repository.renameFolder(id: folder.id, name: newName)
                loadError = nil
            } catch {
                updateFolder(id: previousFolder.id) { $0 = previousFolder }
                loadError = folderErrorMessage(for: error, fallback: "Couldn't rename folder")
            }
        }
    }
    func deleteFolder(_ folder: ClipboardFolder) {
        let previousFolders = folders
        let affectedItems = items.filter { $0.folderID == folder.id }.map { ($0.id, $0.folderID) }
        folders.removeAll { $0.id == folder.id }
        for item in items where item.folderID == folder.id {
            updateItem(id: item.id) { $0.folderID = nil }
        }
        Task {
            do {
                try await repository.deleteFolder(id: folder.id)
                loadError = nil
            } catch {
                folders = previousFolders
                for (itemID, folderID) in affectedItems {
                    updateItem(id: itemID) { $0.folderID = folderID }
                }
                loadError = folderErrorMessage(for: error, fallback: "Couldn't delete folder")
            }
        }
    }
    func assignItems(_ itemIDs: [UUID], to folder: ClipboardFolder) {
        let uniqueIDs = Array(Set(itemIDs))
        guard !uniqueIDs.isEmpty else { return }
        let previousAssignments = Dictionary(uniqueKeysWithValues: uniqueIDs.compactMap { id in
            items.first(where: { $0.id == id }).map { (id, $0.folderID) }
        })
        for id in uniqueIDs {
            updateItem(id: id) { $0.folderID = folder.id }
        }
        Task {
            do {
                try await repository.setFolder(ids: uniqueIDs, folderID: folder.id)
                loadError = nil
            } catch {
                for (itemID, oldFolderID) in previousAssignments {
                    updateItem(id: itemID) { $0.folderID = oldFolderID }
                }
                loadError = folderErrorMessage(for: error, fallback: "Couldn't move item to folder")
            }
        }
    }
    func removeFromFolder(_ item: ClipboardItem) {
        let previousFolderID = item.folderID
        updateItem(id: item.id) { $0.folderID = nil }
        Task {
            do {
                try await repository.setFolder(id: item.id, folderID: nil)
                loadError = nil
            } catch {
                updateItem(id: item.id) { $0.folderID = previousFolderID }
                loadError = folderErrorMessage(for: error, fallback: "Couldn't remove item from folder")
            }
        }
    }
    func copyToPasteboard(_ item: ClipboardItem) {
        Task {
            _ = await restoreToPasteboard(item)
        }
    }
    func restoreToPasteboard(_ item: ClipboardItem, asPlainText: Bool = false) async -> ClipboardRestoreResult {
        let pasteboard = NSPasteboard.general
        if !asPlainText, let rawData = item.rawPasteboardData, !rawData.isEmpty {
            writeRawPasteboardData(rawData, to: pasteboard)
            service.markSelfCopy()
            return ClipboardRestoreResult(didCopy: true, message: "Copied to clipboard")
        }
        if asPlainText {
            guard let text = plainTextFallback(for: item) else {
                return ClipboardRestoreResult(didCopy: false, message: "No plain text available")
            }
            return writePlainText(text, to: pasteboard)
                ? ClipboardRestoreResult(didCopy: true, message: "Copied as plain text")
                : ClipboardRestoreResult(didCopy: false, message: "Could not copy item")
        }
        if item.contentType == .richText {
            return writeRichText(item, to: pasteboard)
                ? ClipboardRestoreResult(didCopy: true, message: "Copied to clipboard")
                : ClipboardRestoreResult(didCopy: false, message: "Could not copy rich text")
        }
        if let url = item.revealableFileURL,
           item.contentType == .file || item.contentType == .video || item.contentType == .image {
            return writeFileURL(url, to: pasteboard)
                ? ClipboardRestoreResult(didCopy: true, message: "Copied to clipboard")
                : ClipboardRestoreResult(didCopy: false, message: "Could not copy file")
        }
        if item.bucket == nil {
            guard let text = item.contentText, !text.isEmpty else {
                return ClipboardRestoreResult(didCopy: false, message: "Nothing to copy")
            }
            return writePlainText(text, to: pasteboard)
                ? ClipboardRestoreResult(didCopy: true, message: "Copied to clipboard")
                : ClipboardRestoreResult(didCopy: false, message: "Could not copy item")
        }
        if let data = item.localData {
            return writeBinary(data, for: item, to: pasteboard)
                ? ClipboardRestoreResult(didCopy: true, message: "Copied to clipboard")
                : ClipboardRestoreResult(didCopy: false, message: "Could not copy item")
        }
        guard item.storagePath != nil else {
            return ClipboardRestoreResult(didCopy: false, message: "Item data is unavailable")
        }
        if let data = try? await repository.downloadData(for: item) {
            updateItem(id: item.id) { $0.localData = data }
            return writeBinary(data, for: item, to: pasteboard)
                ? ClipboardRestoreResult(didCopy: true, message: "Copied to clipboard")
                : ClipboardRestoreResult(didCopy: false, message: "Could not copy item")
        }
        return ClipboardRestoreResult(didCopy: false, message: "Could not restore item")
    }
    private func plainTextFallback(for item: ClipboardItem) -> String? {
        if let text = item.contentText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if let fileName = item.fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !fileName.isEmpty {
            return fileName
        }
        return nil
    }
    func focusInFullApp(_ item: ClipboardItem) {
        focusedItemID = item.id
    }
    func expandInFullApp(_ item: ClipboardItem) {
        focusedItemID = item.id 
        expandedItemID = item.id
    }
    func dragItemProvider(for item: ClipboardItem) -> NSItemProvider {
        if let url = item.revealableFileURL,
           item.contentType == .file || item.contentType == .video || item.contentType == .image {
            return NSItemProvider(object: url as NSURL)
        }
        switch item.contentType {
        case .file, .video:
            break
        case .url:
            if let text = item.contentText, let url = URL(string: text) {
                return NSItemProvider(object: url as NSURL)
            }
        case .text:
            if let text = item.contentText {
                return NSItemProvider(object: text as NSString)
            }
        case .richText:
            let provider = NSItemProvider()
            if let data = item.rtfdData {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtfd.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                return provider
            }
            if let data = item.rtfData {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                return provider
            }
            if let data = item.htmlData {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.html.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                return provider
            }
            if let text = item.contentText {
                return NSItemProvider(object: text as NSString)
            }
        case .image:
            if let data = item.localData {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                return provider
            }
        case .video:
            break
        }
        return NSItemProvider(object: (item.contentText ?? item.fileName ?? "") as NSString)
    }
    func folderDragItemProvider(for itemIDs: [UUID]) -> NSItemProvider {
        let payload = itemIDs.map(\.uuidString).joined(separator: ",")
        let provider: NSItemProvider
        if itemIDs.count == 1, let item = items.first(where: { $0.id == itemIDs[0] }) {
            provider = dragItemProvider(for: item)
        } else {
            let fallbackText = items.filter { itemIDs.contains($0.id) }
                .compactMap { plainTextFallback(for: $0) }
                .joined(separator: "\n")
            provider = NSItemProvider(object: fallbackText as NSString)
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.hetpasteFolderItemIDs.identifier, visibility: .all) { completion in
            completion(payload.data(using: .utf8), nil)
            return nil
        }
        return provider
    }
    private func writeRichText(_ item: ClipboardItem, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let pbItem = NSPasteboardItem()
        if let data = item.rtfdData { pbItem.setData(data, forType: .rtfd) }
        if let data = item.rtfData { pbItem.setData(data, forType: .rtf) }
        if let data = item.htmlData { pbItem.setData(data, forType: .html) }
        if let text = item.contentText { pbItem.setString(text, forType: .string) }
        let didWrite = pasteboard.writeObjects([pbItem])
        service.markSelfCopy()
        return didWrite
    }
    private func writePlainText(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)
        service.markSelfCopy()
        return didWrite
    }
    private func writeFileURL(_ url: URL, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let didWrite = pasteboard.writeObjects([url as NSURL])
        service.markSelfCopy()
        return didWrite
    }
    private func writeBinary(_ data: Data, for item: ClipboardItem, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let didWrite: Bool
        switch item.contentType {
        case .image:
            didWrite = pasteboard.setData(data, forType: .png)
        default:
            didWrite = pasteboard.setData(data, forType: .fileContents)
        }
        service.markSelfCopy()
        return didWrite
    }
    private func writeRawPasteboardData(_ rawData: [String: Data], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let pbItem = NSPasteboardItem()
        for (typeIdentifier, data) in rawData {
            pbItem.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
        }
        pasteboard.writeObjects([pbItem])
    }
    private func updateItem(id: UUID, _ mutate: (inout ClipboardItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }
    private func updateFolder(id: UUID, _ mutate: (inout ClipboardFolder) -> Void) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        mutate(&folders[idx])
    }
    private func mergeFolders(_ remoteFolders: [ClipboardFolder]) -> [ClipboardFolder] {
        let pendingFolders = folders.filter { localFolder in
            pendingFolderIDs.contains(localFolder.id) &&
            !remoteFolders.contains(where: { $0.id == localFolder.id })
        }
        return remoteFolders + pendingFolders
    }
    private func folderErrorMessage(for error: Error, fallback: String) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("user_id") {
            return "Folder schema still requires user_id. Update the folders table for local app access."
        }
        if message.contains("permission") || message.contains("policy") || message.contains("row-level security") {
            return "Folder permissions are blocking this action in Supabase."
        }
        if message.contains("violates foreign key constraint") {
            return "Folder relationship is out of sync. Try reopening the app."
        }
        return fallback
    }
    
    // MARK: - Chain Actions
    
    func activeItems(for chain: Chain) -> [ClipboardItem] {
        let cItems = (chainItems[chain.id] ?? []).sorted { $0.position < $1.position }
        return cItems.compactMap { ci in activeItems.first(where: { $0.id == ci.snippetID }) }
    }

    func createChain(name: String, snippetIDs: [UUID]) {
        let chain = Chain(id: UUID(), name: name, createdAt: Date(), updatedAt: Date())
        var chainItemsForThisChain: [ChainItem] = []
        for (index, snippetID) in snippetIDs.enumerated() {
            chainItemsForThisChain.append(ChainItem(id: UUID(), chainID: chain.id, snippetID: snippetID, position: index))
        }
        
        chains.append(chain)
        chainItems[chain.id] = chainItemsForThisChain
        
        Task {
            do {
                try await repository.createChain(id: chain.id, name: name)
                try await repository.addChainItems(chainItemsForThisChain, chainID: chain.id)
            } catch {
                print("Failed to create chain: \(error)")
                self.chains.removeAll { $0.id == chain.id }
                self.chainItems.removeValue(forKey: chain.id)
            }
        }
    }
    
    func renameChain(_ chain: Chain, name: String) {
        guard let index = chains.firstIndex(where: { $0.id == chain.id }) else { return }
        let oldName = chains[index].name
        chains[index].name = name
        chains[index].updatedAt = Date()
        
        Task {
            do {
                try await repository.renameChain(id: chain.id, name: name)
            } catch {
                print("Failed to rename chain: \(error)")
                DispatchQueue.main.async {
                    self.chains[index].name = oldName
                }
            }
        }
    }
    
    func updateChain(_ chain: Chain, name: String, snippetIDs: [UUID]) {
        guard let index = chains.firstIndex(where: { $0.id == chain.id }) else { return }
        
        let oldName = chains[index].name
        let oldItems = chainItems[chain.id]
        
        chains[index].name = name
        chains[index].updatedAt = Date()
        
        var newChainItems: [ChainItem] = []
        for (idx, snippetID) in snippetIDs.enumerated() {
            newChainItems.append(ChainItem(id: UUID(), chainID: chain.id, snippetID: snippetID, position: idx))
        }
        
        chainItems[chain.id] = newChainItems
        
        Task {
            do {
                if oldName != name {
                    try await repository.renameChain(id: chain.id, name: name)
                }
                try await repository.deleteChainItems(chainID: chain.id)
                if !newChainItems.isEmpty {
                    try await repository.addChainItems(newChainItems, chainID: chain.id)
                }
            } catch {
                print("Failed to update chain: \(error)")
                DispatchQueue.main.async {
                    self.chains[index].name = oldName
                    self.chainItems[chain.id] = oldItems
                }
            }
        }
    }
    
    func deleteChain(_ chain: Chain) {
        guard let index = chains.firstIndex(where: { $0.id == chain.id }) else { return }
        let removedChain = chains.remove(at: index)
        let removedItems = chainItems.removeValue(forKey: chain.id)
        
        Task {
            do {
                try await repository.deleteChain(id: chain.id)
            } catch {
                print("Failed to delete chain: \(error)")
                self.chains.insert(removedChain, at: index)
                self.chainItems[chain.id] = removedItems
            }
        }
    }
    
    func updateChainItems(chain: Chain, snippetIDs: [UUID]) {
        let oldItems = chainItems[chain.id]
        
        var newChainItems: [ChainItem] = []
        for (index, snippetID) in snippetIDs.enumerated() {
            newChainItems.append(ChainItem(id: UUID(), chainID: chain.id, snippetID: snippetID, position: index))
        }
        
        chainItems[chain.id] = newChainItems
        
        Task {
            do {
                try await repository.deleteChainItems(chainID: chain.id)
                try await repository.addChainItems(newChainItems, chainID: chain.id)
            } catch {
                print("Failed to update chain items: \(error)")
                self.chainItems[chain.id] = oldItems
            }
        }
    }
    
    func pasteChain(_ chain: Chain) {
        guard let items = chainItems[chain.id] else { return }
        
        let sortedChainItems = items.sorted { $0.position < $1.position }
        let clipboardItemsToPaste = sortedChainItems.compactMap { ci in
            self.items.first(where: { $0.id == ci.snippetID })
        }
        
        guard !clipboardItemsToPaste.isEmpty else { return }
        
        psychoCopyManager.clearQueue()
        psychoCopyManager.activateMultiCopyMode()
        
        for item in clipboardItemsToPaste {
            psychoCopyManager.handleClipboardChange(item)
        }
    }
}
extension ClipboardHistoryViewModel {
    func performSequentialPaste() {
        Task {
            _ = await psychoCopyManager.performSequentialPaste(viewModel: self)
        }
    }
    func performReverseSequentialPaste() {
        Task {
            _ = await psychoCopyManager.performReverseSequentialPaste(viewModel: self)
        }
    }
    func toggleMultiCopyMode() {
        psychoCopyManager.toggleMultiCopyMode()
    }
    func clearCopyQueue() {
        psychoCopyManager.clearQueue()
    }
}