import CloudKit
import Combine
import Foundation
import SwiftUI
import UIKit

extension Notification.Name {
    static let iosLibraryDidChange = Notification.Name("iosLibraryDidChange")
}

/// Serializes all iOS CloudKit reads. Both the foreground UI and an APNs wake
/// use this object, so a push can never race the fallback timer and advance the
/// zone-change token before the other reader has applied its records.
@MainActor
final class IOSCloudLibrarySync {
    static let shared = IOSCloudLibrarySync()

    private var isSyncing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    @discardableResult
    func sync() async throws -> Bool {
        if isSyncing {
            await withCheckedContinuation { waiters.append($0) }
            return false
        }

        isSyncing = true
        defer {
            isSyncing = false
            let currentWaiters = waiters
            waiters.removeAll()
            currentWaiters.forEach { $0.resume() }
        }

        let store = LibraryMetadataStore.shared
        let repository = ClipboardRepository()
        let accountIdentifier = try await CloudKitManager.shared.currentAccountIdentifier()
        if store.resetIfAccountChanged(to: accountIdentifier) {
            CloudKitManager.shared.discardChangeToken()
        }

        // A token alone is not a local library. Bootstrap the durable index
        // once, so an app restore or a previously persisted token can never
        // leave the phone showing an empty library until another change occurs.
        if store.needsInitialRemoteBootstrap() {
            let items = try await repository.fetchRecent(limit: 100)
            async let folders = repository.fetchFolders()
            async let chains = repository.fetchChains()
            store.upsert(items: items, folders: try await folders, chains: try await chains)
            store.markInitialRemoteBootstrapComplete()
            await MainActor.run { NotificationCenter.default.post(name: .iosLibraryDidChange, object: nil) }
        }

        let delta = try await LibrarySyncCoordinator.shared.sync()
        if delta.hasChanges {
            await MainActor.run {
                NotificationCenter.default.post(name: .iosLibraryDidChange, object: nil)
            }
        }
        await MainActor.run { CloudSyncDiagnostics.shared.recordSuccess(source: "iOS live sync", delta: delta) }
        return delta.hasChanges
    }
}

@MainActor
final class IOSClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var folders: [ClipboardFolder] = []
    @Published private(set) var chains: [Chain] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private let store = LibraryMetadataStore.shared
    private let repository = ClipboardRepository()
    private var hasLoadedInitial = false
    private var automaticSyncTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    private var syncAgainWhenFinished = false
    private var pendingDebouncedSync: Task<Void, Never>?
    private var pendingItemIDs: Set<UUID> = []
    private var outboxTask: Task<Void, Never>?
    private var pendingFolderIDs: Set<UUID> = []
    private var folderOutboxTask: Task<Void, Never>?

    /// Silent pushes are the immediate path. This only recovers when iOS
    /// coalesces or delays a push while the app is already visible. Simulators
    /// do not receive APNs delivery, so their foreground fallback is shorter
    /// for reliable side-by-side Mac/iPhone development.
    #if targetEnvironment(simulator)
    private static let foregroundFallbackInterval: Duration = .seconds(3)
    #else
    private static let foregroundFallbackInterval: Duration = .seconds(15)
    #endif

    init() {
        // The edit outbox must not depend on an unstarted path monitor. Start
        // it here (rather than only in the macOS view model) and retry queued
        // writes immediately when iOS reports a usable transport again.
        NetworkReachability.shared.start()
        NotificationCenter.default.publisher(for: .iosLibraryDidChange)
            .sink { [weak self] _ in self?.loadFromLocalStore() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .hetpasteNetworkBecameAvailable)
            .sink { [weak self] _ in
                self?.retryPendingItemUploads()
                self?.retryPendingFolderUploads()
                self?.requestSync(silent: true)
            }
            .store(in: &cancellables)
    }

    func load() {
        if !hasLoadedInitial {
            loadFromLocalStore()
            hasLoadedInitial = true
        }
        startAutomaticSyncLoop()
        requestSync()
    }

    func refresh() async {
        await syncRemoteDeltas()
    }

    func startAutomaticSyncLoop() {
        automaticSyncTask?.cancel()
        automaticSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.foregroundFallbackInterval)
                guard !Task.isCancelled, let self else { return }
                guard NetworkReachability.shared.isOnline else { continue }
                self.requestSync(silent: true)
            }
        }
    }

    func stopAutomaticSyncLoop() {
        automaticSyncTask?.cancel()
        automaticSyncTask = nil
    }

    private func loadFromLocalStore() {
        let initial = store.loadInitial(itemLimit: 100)
        pendingItemIDs = initial.queues.pendingItemIDs
        pendingFolderIDs = initial.queues.pendingFolderIDs
        let newItems = initial.items
            .filter { !$0.isDeleted }
            .sorted(by: Self.newestFirst)
        let newFolders = initial.folders.sorted { $0.createdAt < $1.createdAt }
        let newChains = initial.chains.sorted { $0.createdAt < $1.createdAt }

        if newItems != items || newFolders != folders || newChains != chains {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.items = newItems
                self.folders = newFolders
                self.chains = newChains
            }
        }
        retryPendingItemUploads()
        retryPendingFolderUploads()
    }

    private func requestSync(silent: Bool = false) {
        if silent { pendingDebouncedSync?.cancel() }
        pendingDebouncedSync = Task { @MainActor [weak self] in
            // Coalesce a burst of CloudKit pushes into one token delta fetch.
            if silent { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await self?.syncRemoteDeltas(silent: silent)
        }
    }

    func syncRemoteDeltas(silent: Bool = false) async {
        guard !isSyncing else {
            syncAgainWhenFinished = true
            return
        }
        isSyncing = true
        if !silent {
            isLoading = true
        }
        defer {
            isSyncing = false
            if !silent {
                isLoading = false
            }
            if syncAgainWhenFinished {
                syncAgainWhenFinished = false
                requestSync(silent: true)
            }
        }

        do {
            _ = try await IOSCloudLibrarySync.shared.sync()
            // Remote changes never overwrite IDs in the durable item queue.
            // Flush local edits after the delta so their parent revision is
            // based on the newest known server state.
            retryPendingItemUploads()
            retryPendingFolderUploads()
            let applyStartedAt = Date()
            loadFromLocalStore()
            CloudSyncDiagnostics.shared.recordUIApply(duration: Date().timeIntervalSince(applyStartedAt))
            loadError = nil
        } catch {
            // Keep the already-indexed library visible. Retrying a full query
            // for every transient error was slow, duplicated CloudKit work and
            // could reorder cards while a delta import was in flight.
            if !silent {
                loadError = error.localizedDescription
            }
        }
    }

    func itemCount(inFolder folderID: UUID) -> Int {
        let count = store.itemCount(inFolder: folderID)
        if count > 0 { return count }
        return items.filter { $0.folderIDs.contains(folderID) }.count
    }

    func createFolder(name: String) {
        let folder = ClipboardFolder(name: name)
        folders.append(folder)
        store.upsert(folders: [folder])
        pendingFolderIDs.insert(folder.id)
        persistItemOutbox()
        retryPendingFolderUploads()
    }

    func copy(_ item: ClipboardItem) {
        Task { [weak self] in
            guard let self else { return }
            var itemToCopy = item
            if (CloudChunkManifest(storagePath: item.storagePath)?.kind == .richPayload)
                || item.storagePath?.hasPrefix(CloudClipboardPayload.storagePrefix) == true {
                do {
                    guard let hydrated = try await self.repository.hydrateRichPayload(for: item) else {
                        self.loadError = "Couldn’t download the full rich-text item."
                        return
                    }
                    itemToCopy = hydrated
                    if let index = self.items.firstIndex(where: { $0.id == item.id }) { self.items[index] = hydrated }
                } catch {
                    self.loadError = error.localizedDescription
                    return
                }
            }
            let clipboard = IOSClipboardProvider.shared
            if itemToCopy.contentType == .text,
               PortableClipboardColor.parse(itemToCopy.contentText) != nil,
               clipboard.copyColor(itemToCopy.contentText) {
                return
            }
            switch itemToCopy.contentType {
        case .richText:
            clipboard.copyRichText(plainText: itemToCopy.contentText, rtfData: itemToCopy.rtfData, htmlData: itemToCopy.htmlData, rtfdData: itemToCopy.rtfdData)
        case .text:
            if itemToCopy.rtfData != nil || itemToCopy.htmlData != nil || itemToCopy.rtfdData != nil {
                clipboard.copyRichText(plainText: itemToCopy.contentText, rtfData: itemToCopy.rtfData, htmlData: itemToCopy.htmlData, rtfdData: itemToCopy.rtfdData)
            } else if let text = itemToCopy.contentText {
                clipboard.copyText(text)
            }
        case .url:
            if let text = itemToCopy.contentText, let url = URL(string: text) {
                clipboard.copyURL(url)
            } else if let text = itemToCopy.contentText {
                clipboard.copyText(text)
            }
        case .image:
            do {
                let data = try await self.fullAssetData(for: itemToCopy)
                clipboard.copyImage(data: data)
            } catch {
                self.loadError = error.localizedDescription
            }
        case .file, .video:
            do {
                let data = try await self.fullAssetData(for: itemToCopy)
                clipboard.copyFileData(data, fileName: itemToCopy.fileName)
            } catch {
                if let text = itemToCopy.contentText ?? itemToCopy.fileName {
                    clipboard.copyText(text)
                } else {
                    self.loadError = error.localizedDescription
                }
            }
        }
        }
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        Task { [weak self] in
            guard let self else { return }
            var resolved = item
            if CloudChunkManifest(storagePath: item.storagePath)?.kind == .richPayload
                || item.storagePath?.hasPrefix(CloudClipboardPayload.storagePrefix) == true {
                do {
                    guard let hydrated = try await repository.hydrateRichPayload(for: item) else {
                        loadError = "Couldn’t download the full rich-text item."
                        return
                    }
                    resolved = hydrated
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = hydrated }
                } catch {
                    loadError = error.localizedDescription
                    return
                }
            }
            guard let text = resolved.contentText ?? resolved.fileName, !text.isEmpty else { return }
            IOSClipboardProvider.shared.copyText(text)
        }
    }

    /// Applies the edit locally first. The editor must never be held open by a
    /// slow/offline CloudKit request; the durable local index remains the
    /// source of truth until the background upload completes.
    func updateItemContent(id: UUID, contentText: String?, rtfData: Data?, htmlData: Data?, rtfdData: Data?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        // Make independent Foundation values before the UIKit editor is
        // dismissed. This avoids retaining an attributed-text backing buffer
        // across the background CloudKit upload.
        let stableRTF = rtfData.map { Data(NSData(data: $0)) }
        let stableHTML = htmlData.map { Data(NSData(data: $0)) }
        let stableRTFD = rtfdData.map { Data(NSData(data: $0)) }
        items[index].contentText = contentText
        items[index].rtfData = stableRTF
        items[index].htmlData = stableHTML
        items[index].rtfdData = stableRTFD
        if stableRTF != nil || stableHTML != nil || stableRTFD != nil {
            items[index].contentType = .richText
        }
        items[index].updatedAt = Date()
        items[index].syncStatus = .pending
        store.upsert(items: [items[index]])
        enqueueItemUpload(id)
        return true
    }

    /// The SQLite row contains the full edit payload; this set is the durable
    /// outbox journal. A force-quit, offline edit, or CloudKit retry therefore
    /// resumes on the next launch instead of silently losing formatting.
    private func enqueueItemUpload(_ id: UUID) {
        pendingItemIDs.insert(id)
        persistItemOutbox()
        retryPendingItemUploads()
    }

    private func persistItemOutbox() {
        var queues = store.loadInitial(itemLimit: 0).queues
        queues.pendingItemIDs = pendingItemIDs
        queues.pendingFolderIDs = pendingFolderIDs
        store.saveQueues(queues)
    }

    private func retryPendingFolderUploads() {
        guard folderOutboxTask == nil, !pendingFolderIDs.isEmpty else { return }
        folderOutboxTask = Task { @MainActor [weak self] in
            defer { self?.folderOutboxTask = nil }
            guard let self else { return }
            let foldersByID = Dictionary(uniqueKeysWithValues: self.store.loadInitial(itemLimit: 0).folders.map { ($0.id, $0) })
            for id in self.pendingFolderIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let folder = foldersByID[id] else { self.pendingFolderIDs.remove(id); self.persistItemOutbox(); continue }
                do {
                    _ = try await CloudKitManager.shared.save(folder.cloudRecord())
                    self.pendingFolderIDs.remove(id)
                    self.persistItemOutbox()
                } catch {
                    self.loadError = error.localizedDescription
                    break
                }
            }
        }
    }

    private func retryPendingItemUploads() {
        // A path monitor is only a hint and may not have emitted its first
        // update yet. Always attempt an explicitly queued user edit; CloudKit
        // gives the authoritative offline/retry error and the item remains in
        // the durable outbox if it cannot be sent.
        guard outboxTask == nil, !pendingItemIDs.isEmpty else { return }
        outboxTask = Task { @MainActor [weak self] in
            defer { self?.outboxTask = nil }
            guard let self else { return }
            for id in self.pendingItemIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard !Task.isCancelled else { return }
                // Read the latest SQLite value, not a captured SwiftUI value.
                // This prevents an older upload from overwriting a rapid next edit.
                guard let item = self.store.item(id: id) else {
                    self.pendingItemIDs.remove(id); self.persistItemOutbox(); continue
                }
                let revision = item.updatedAt
                do {
                    let saved = try await self.repository.save(item)
                    guard let current = self.store.item(id: id), current.updatedAt == revision else { continue }
                    self.pendingItemIDs.remove(id)
                    self.persistItemOutbox()
                    if let index = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[index].storagePath = saved.storagePath
                        self.items[index].syncStatus = .synced
                        self.store.upsert(items: [self.items[index]])
                    }
                } catch let conflict as ClipboardContentConflictError {
                    self.preserveContentConflict(conflict)
                } catch {
                    if let index = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[index].syncStatus = .failed
                        self.store.upsert(items: [self.items[index]])
                    }
                    self.loadError = error.localizedDescription
                    break
                }
            }
        }
    }

    /// Never discard an offline edit merely because another device committed
    /// first. Keep the server version at its original ID and upload the local
    /// revision as an explicitly named, independently syncable conflict copy.
    private func preserveContentConflict(_ conflict: ClipboardContentConflictError) {
        var localCopy = conflict.local
        localCopy.id = UUID()
        localCopy.createdAt = Date()
        localCopy.updatedAt = localCopy.createdAt
        localCopy.sourceAppName = "\(localCopy.sourceAppName) — Conflict Copy"
        localCopy.syncStatus = .pending

        if let index = items.firstIndex(where: { $0.id == conflict.server.id }) {
            items[index] = conflict.server
        } else {
            items.append(conflict.server)
        }
        items.append(localCopy)
        store.upsert(items: [conflict.server, localCopy])
        pendingItemIDs.remove(conflict.server.id)
        pendingItemIDs.insert(localCopy.id)
        persistItemOutbox()
        loadError = "Another device edited this card first. Your edit was preserved as a Conflict Copy."
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.retryPendingItemUploads()
        }
    }

    func materializedAssetURL(for item: ClipboardItem) async throws -> URL {
        let data = try await fullAssetData(for: item)

        let fileExtension = URL(fileURLWithPath: item.fileName ?? "").pathExtension
        let fallbackExtension: String
        switch item.contentType {
        case .image: fallbackExtension = "png"
        case .video: fallbackExtension = "mov"
        default: fallbackExtension = "dat"
        }
        let ext = fileExtension.isEmpty ? fallbackExtension : fileExtension
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sniphet-Previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(item.id.uuidString)-\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func fullAssetData(for item: ClipboardItem) async throws -> Data {
        if let localData = item.localData { return localData }
        if let downloaded = try await repository.downloadData(for: item) { return downloaded }
        throw CocoaError(.fileNoSuchFile)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        let newValue = !item.isPinned
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned = newValue
        items[index].updatedAt = Date()
        items[index].syncStatus = .pending
        store.upsert(items: [items[index]])
        enqueueItemUpload(item.id)
    }

    private static func newestFirst(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
