import CloudKit
import Combine
import Foundation

/// Privacy-safe sync health data for the Settings screen. No clipboard content,
/// record IDs, or account identifiers are stored here.
@MainActor
final class CloudSyncDiagnostics: ObservableObject {
    static let shared = CloudSyncDiagnostics()

    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncSource = "—"
    @Published private(set) var lastPushReceivedAt: Date?
    @Published private(set) var lastImportedChangeCount = 0
    @Published private(set) var lastDeletedChangeCount = 0
    @Published private(set) var lastIgnoredChunkCount = 0
    @Published private(set) var lastSyncDuration: TimeInterval = 0
    @Published private(set) var lastCloudFetchDuration: TimeInterval = 0
    @Published private(set) var lastLocalApplyDuration: TimeInterval = 0
    @Published private(set) var lastUIApplyDuration: TimeInterval = 0
    @Published private(set) var lastRichPayloadHydrationDuration: TimeInterval = 0
    @Published private(set) var nextRetryAt: Date?
    @Published private(set) var queuedOperationCount = 0
    @Published private(set) var transferCompletedBytes: Int64 = 0
    @Published private(set) var transferTotalBytes: Int64 = 0
    @Published private(set) var isLargeTransferActive = false
    private var libraryQueueCount = 0
    private var wardrobeQueueCount = 0

    private init() {}

    func updateQueueCount(_ count: Int) {
        libraryQueueCount = count
        queuedOperationCount = libraryQueueCount + wardrobeQueueCount
    }

    func updateWardrobeQueueCount(_ count: Int) {
        wardrobeQueueCount = count
        queuedOperationCount = libraryQueueCount + wardrobeQueueCount
    }
    func recordSuccess(source: String = "foreground", importedChanges: Int = 0) {
        lastSuccessfulSync = Date(); lastError = nil; nextRetryAt = nil; lastSyncSource = source
        lastImportedChangeCount = importedChanges; lastDeletedChangeCount = 0; lastIgnoredChunkCount = 0; lastSyncDuration = 0
        lastCloudFetchDuration = 0; lastLocalApplyDuration = 0
    }
    func recordSuccess(source: String, delta: CloudSyncDelta) {
        lastSuccessfulSync = Date(); lastError = nil; nextRetryAt = nil; lastSyncSource = source
        lastImportedChangeCount = delta.insertedOrUpdated; lastDeletedChangeCount = delta.deleted
        lastIgnoredChunkCount = delta.ignoredAssetChunks; lastSyncDuration = delta.elapsed
        lastCloudFetchDuration = delta.fetchElapsed; lastLocalApplyDuration = delta.applyElapsed
    }
    func recordPushReceived() { lastPushReceivedAt = Date() }
    func recordUIApply(duration: TimeInterval) { lastUIApplyDuration = duration }
    func recordRichPayloadHydration(duration: TimeInterval) { lastRichPayloadHydrationDuration = duration }

    func beginLargeTransfer(totalBytes: Int64, completedBytes: Int64 = 0) {
        transferTotalBytes = totalBytes
        transferCompletedBytes = min(completedBytes, totalBytes)
        isLargeTransferActive = true
    }

    func advanceLargeTransfer(by bytes: Int64) {
        transferCompletedBytes = min(transferTotalBytes, transferCompletedBytes + bytes)
    }

    func finishLargeTransfer() {
        transferCompletedBytes = transferTotalBytes
        isLargeTransferActive = false
    }

    func failLargeTransfer() { isLargeTransferActive = false }

    func recordFailure(_ error: Error) {
        lastError = error.localizedDescription
        guard let cloudError = error as? CKError else { return }
        if let seconds = (cloudError as NSError).userInfo[CKErrorRetryAfterKey] as? NSNumber {
            nextRetryAt = Date().addingTimeInterval(seconds.doubleValue)
        }
    }

    func recordBackgroundSchedulingFailure(_ error: Error) { lastError = "Background refresh: \(error.localizedDescription)" }
}
