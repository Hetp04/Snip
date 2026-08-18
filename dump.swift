import Foundation
import CloudKit

@available(macOS 14.0, *)
class MockDelegate: @unchecked Sendable, CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {}
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? { return nil }
}

@available(macOS 14.0, *)
func dump() async throws {
    let engine = CKSyncEngine(CKSyncEngine.Configuration(database: CKContainer.default().privateCloudDatabase, stateSerialization: nil, delegate: MockDelegate()))
    try await engine.fetchChanges()
}
