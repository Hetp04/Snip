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

        let changed = try await CloudKitManager.shared.consumeRemoteChanges(
            onRecordsChanged: { LibraryMetadataStore.shared.applyRemoteRecords($0) },
            onRecordsDeleted: { LibraryMetadataStore.shared.applyRemoteDeletions($0) },
            onPageApplied: {
                Task { @MainActor in NotificationCenter.default.post(name: .iosLibraryDidChange, object: nil) }
            }
        )
        if changed {
            await MainActor.run {
                NotificationCenter.default.post(name: .iosLibraryDidChange, object: nil)
            }
        }
        await MainActor.run { CloudSyncDiagnostics.shared.recordSuccess(source: "iOS live sync", importedChanges: changed ? 1 : 0) }
        return changed
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
    private var hasLoadedInitial = false
    private var automaticSyncTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    private var syncAgainWhenFinished = false

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
        NotificationCenter.default.publisher(for: .iosLibraryDidChange)
            .sink { [weak self] _ in self?.loadFromLocalStore() }
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
    }

    private func requestSync(silent: Bool = false) {
        Task { @MainActor [weak self] in
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
            loadFromLocalStore()
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
        Task {
            do {
                let record = folder.cloudRecord()
                _ = try await CloudKitManager.shared.save(record)
                loadFromLocalStore()
            } catch {
                folders.removeAll { $0.id == folder.id }
                store.remove(folders: [folder.id])
                loadError = error.localizedDescription
            }
        }
    }

    func copy(_ item: ClipboardItem) {
        let clipboard = IOSClipboardProvider.shared
        switch item.contentType {
        case .richText:
            clipboard.copyRichText(plainText: item.contentText, rtfData: item.rtfData, htmlData: item.htmlData)
        case .text:
            if item.rtfData != nil || item.htmlData != nil {
                clipboard.copyRichText(plainText: item.contentText, rtfData: item.rtfData, htmlData: item.htmlData)
            } else if let text = item.contentText {
                clipboard.copyText(text)
            }
        case .url:
            if let text = item.contentText, let url = URL(string: text) {
                clipboard.copyURL(url)
            } else if let text = item.contentText {
                clipboard.copyText(text)
            }
        case .image:
            if let data = item.localData ?? ThumbnailCache.shared.data(for: item.id) {
                clipboard.copyImage(data: data)
            }
        case .file, .video:
            if let text = item.contentText ?? item.fileName {
                clipboard.copyText(text)
            }
        }
    }

    func toggleFavorite(_ item: ClipboardItem) {
        let newValue = !item.isPinned
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned = newValue
        items[index].updatedAt = Date()
        store.upsert(items: [items[index]])
        Task {
            do {
                _ = try await ClipboardRepository().save(items[index])
            } catch {
                guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
                items[currentIndex].isPinned.toggle()
                items[currentIndex].updatedAt = item.updatedAt
                store.upsert(items: [items[currentIndex]])
                loadError = error.localizedDescription
            }
        }
    }

    private static func newestFirst(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
