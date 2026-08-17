import Foundation

/// Serializes large asset transfers. Normal metadata saves use CloudKit
/// directly, while only one bulk upload/download runs at a time at utility
/// priority so a giant clipboard capture cannot flood the network.
actor LargeTransferScheduler {
    static let shared = LargeTransferScheduler()
    /// A separate serial lane for thumbnail migration. It must not share the
    /// chunk-transfer lock because downloading a chunked image acquires `shared`.
    static let preview = LargeTransferScheduler()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isBusy else { isBusy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
