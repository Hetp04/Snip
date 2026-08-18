import SwiftUI

extension Notification.Name {
    static let focusClipboardSearch = Notification.Name("focusClipboardSearch")
}

@main
struct hetpasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            if RuntimeEnvironment.isRunningUnitTests {
                Text("Running Unit Tests")
            } else {
                ContentView(viewModel: appDelegate.viewModel)
            }
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    if !RuntimeEnvironment.isRunningUnitTests {
                        appDelegate.openMainAppFocusedOnSearch()
                    }
                }
                .keyboardShortcut("f", modifiers: [.option])
            }
        }
        Settings {
            if !RuntimeEnvironment.isRunningUnitTests {
                SettingsView(manager: appDelegate.viewModel.psychoCopyManager, viewModel: appDelegate.viewModel)
            } else {
                Text("Running Unit Tests")
            }
        }
    }
}
