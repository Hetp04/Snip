import Foundation
import Testing
@testable import hetpaste

@Suite("CloudKit reliability")
struct CloudKitReliabilityTests {
    @Test func chunkManifestRoundTripsAndVerifiesIntegrity() {
        let data = Data((0..<70_000).map { UInt8($0 % 251) })
        let manifest = CloudChunkManifest(kind: .binary, data: data, chunkSize: 16_384)
        let restored = CloudChunkManifest(storagePath: manifest.storagePath)
        #expect(restored == manifest)
        #expect(restored?.isValid(data) == true)

        var altered = data
        altered[0] ^= 0xFF
        #expect(restored?.isValid(altered) == false)
    }

    @Test func chunkManifestRejectsMalformedStorageMetadata() {
        #expect(CloudChunkManifest(storagePath: "cloud-chunks-v1:binary:0:12:abc") == nil)
        #expect(CloudChunkManifest(storagePath: "cloud-chunks-v1:unknown:1:12:abc") == nil)
        #expect(CloudChunkManifest(storagePath: "not-a-manifest") == nil)
    }

    @Test func vectorCodecRoundTripsCompactly() {
        let vector = [0.125, -1.5, 42.25]
        let data = CloudKitVectorCodec.encode(vector)
        #expect(data.count == vector.count * MemoryLayout<UInt32>.size)
        let decoded = CloudKitVectorCodec.decode(data)
        #expect(decoded?.count == vector.count)
        #expect(abs((decoded?[1] ?? 0) + 1.5) < 0.0001)
    }

    @Test func cachedSnapshotPersistsDeletionIntent() {
        let id = UUID()
        let snapshot = LibrarySnapshot(
            items: [], folders: [], chains: [], chainItems: [:],
            pendingItemIDs: [], pendingFolderIDs: [], pendingDeletionIDs: [id], savedAt: Date()
        )
        #expect(snapshot.pendingDeletionIDs == [id])
    }

    @Test func offlineEditCarriesAStableModificationTime() {
        var item = ClipboardItem(contentType: .text, contentText: "draft", sourceAppName: "Test")
        #expect(item.updatedAt == nil)
        item.updatedAt = Date()
        #expect(item.updatedAt != nil)
    }
}

@Suite("Clipboard history privacy ranges")
struct ClipboardHistoryRangeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func rollingRangesUseExactElapsedTime() {
        let hour = ClipboardHistoryRange.lastHour.bounds(now: now)
        let day = ClipboardHistoryRange.last24Hours.bounds(now: now)
        let week = ClipboardHistoryRange.last7Days.bounds(now: now)
        #expect(hour.start == now.addingTimeInterval(-3_600))
        #expect(day.start == now.addingTimeInterval(-86_400))
        #expect(week.start == now.addingTimeInterval(-604_800))
        #expect(hour.end == now)
    }

    @Test func todayUsesTheLocalCalendarBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let bounds = ClipboardHistoryRange.today.bounds(now: now, calendar: calendar)
        #expect(bounds.start == calendar.startOfDay(for: now))
        #expect(bounds.end == now)
    }

    @Test func customRangeNormalizesReversedDates() {
        let earlier = now.addingTimeInterval(-100)
        let bounds = ClipboardHistoryRange.custom(start: now, end: earlier).bounds(now: now)
        #expect(bounds.start == earlier)
        #expect(bounds.end == now)
    }

    @Test func allHistoryIsUnbounded() {
        let bounds = ClipboardHistoryRange.allHistory.bounds(now: now)
        #expect(bounds.start == nil)
        #expect(bounds.end == nil)
        #expect(ClipboardHistoryRange.allHistory.contains(.distantPast, now: now))
        #expect(ClipboardHistoryRange.allHistory.contains(.distantFuture, now: now))
    }
}
