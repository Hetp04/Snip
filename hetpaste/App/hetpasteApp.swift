import SwiftUI

extension Notification.Name {
    static let focusClipboardSearch = Notification.Name("focusClipboardSearch")
}

@main
struct hetpasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: appDelegate.viewModel)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    appDelegate.openMainAppFocusedOnSearch()
                }
                .keyboardShortcut("f", modifiers: [.option])
            }
        }
        Settings {
            SettingsView(manager: appDelegate.viewModel.psychoCopyManager, viewModel: appDelegate.viewModel)
        }
    }
}
