import Foundation
import CloudKit

@available(macOS 14.0, *)
func dump() {
    let engine = CKSyncEngine(CKSyncEngine.Configuration(database: CKContainer.default().privateCloudDatabase, stateSerialization: nil, delegate: nil!))
    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: "Zone"))])
}
