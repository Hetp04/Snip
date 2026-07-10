import SwiftUI
@main
struct hetpasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: appDelegate.viewModel)
        }
        Settings {
            SettingsView(manager: appDelegate.viewModel.psychoCopyManager)
        }
    }
}