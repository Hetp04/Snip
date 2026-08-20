import CloudKit
import BackgroundTasks
import SwiftUI
import UIKit

final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    private static let refreshTaskIdentifier = "Her.hetpaste-iOS.library-refresh"
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
        scheduleBackgroundRefresh()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) { scheduleBackgroundRefresh() }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { CloudSyncDiagnostics.shared.recordBackgroundSchedulingFailure(error) }
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task {
            do { _ = try await IOSCloudLibrarySync.shared.sync(); task.setTaskCompleted(success: true) }
            catch { task.setTaskCompleted(success: false) }
        }
        task.expirationHandler = { work.cancel() }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let dict = userInfo as? [String: NSObject],
           let notification = CKNotification(fromRemoteNotificationDictionary: dict) {
            if notification.subscriptionID == "clipboard-library-zone-changes" {
                Task { @MainActor in CloudSyncDiagnostics.shared.recordPushReceived() }
                // Complete the background fetch only after the token-based
                // import has committed to the local index. Posting a message
                // and immediately completing let iOS suspend the app before
                // the view model had a chance to start the actual sync.
                Task {
                    do {
                        let changed = try await IOSCloudLibrarySync.shared.sync()
                        completionHandler(changed ? .newData : .noData)
                    } catch {
                        completionHandler(.failed)
                    }
                }
                return
            }
        }
        completionHandler(.noData)
    }
}

@main
struct hetpaste_iOSApp: App {
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
