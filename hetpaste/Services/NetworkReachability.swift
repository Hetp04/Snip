import Foundation
import Network

extension Notification.Name {
    static let hetpasteNetworkBecameAvailable = Notification.Name("hetpaste.network-became-available")
}

/// A single lightweight path monitor. It never declares CloudKit healthy; it
/// merely tells the sync layer that the device regained a usable network path.
final class NetworkReachability {
    static let shared = NetworkReachability()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.hetpaste.network-reachability")
    private var wasOnline = false
    private var started = false
    private let lock = NSLock()

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isOnline = path.status == .satisfied
            self.lock.lock()
            let becameOnline = isOnline && !self.wasOnline
            self.wasOnline = isOnline
            self.lock.unlock()
            if becameOnline {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .hetpasteNetworkBecameAvailable, object: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }
}
