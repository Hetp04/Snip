import Foundation

/// Durable progress for an in-flight large clipboard upload. The clipboard
/// bytes remain in `AssetCache`; this file contains metadata only, never user
/// clipboard content.
struct CloudChunkTransferState: Codable, Equatable {
    let itemID: UUID
    let manifest: CloudChunkManifest
    var completedIndexes: Set<Int>
    let startedAt: Date
    var updatedAt: Date
}

final class CloudChunkTransferStore {
    static let shared = CloudChunkTransferStore()

    private let lock = NSLock()
    private let fileURL: URL
    private var states: [UUID: CloudChunkTransferState]

    private init(fileManager: FileManager = .default) {
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("hetpaste", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("chunk-transfer-state.json")
        states = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([UUID: CloudChunkTransferState].self, from: $0) } ?? [:]
    }

    func begin(itemID: UUID, manifest: CloudChunkManifest) -> CloudChunkTransferState {
        lock.lock(); defer { lock.unlock() }
        if let existing = states[itemID], existing.manifest == manifest { return existing }
        let state = CloudChunkTransferState(itemID: itemID, manifest: manifest, completedIndexes: [], startedAt: Date(), updatedAt: Date())
        states[itemID] = state
        persistLocked()
        AssetCache.shared.setProtected(true, for: itemID)
        return state
    }

    func markCompleted(itemID: UUID, index: Int) {
        lock.lock(); defer { lock.unlock() }
        guard var state = states[itemID] else { return }
        state.completedIndexes.insert(index)
        state.updatedAt = Date()
        states[itemID] = state
        persistLocked()
    }

    func state(for itemID: UUID) -> CloudChunkTransferState? {
        lock.lock(); defer { lock.unlock() }
        return states[itemID]
    }

    func allStates() -> [CloudChunkTransferState] {
        lock.lock(); defer { lock.unlock() }
        return Array(states.values)
    }

    func complete(itemID: UUID) {
        lock.lock(); defer { lock.unlock() }
        states[itemID] = nil
        persistLocked()
        AssetCache.shared.setProtected(false, for: itemID)
    }

    /// Discards a transfer which cannot be resumed because its durable local
    /// source has been removed. The caller deletes the corresponding remote
    /// chunk records first.
    func discard(itemID: UUID) {
        complete(itemID: itemID)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
