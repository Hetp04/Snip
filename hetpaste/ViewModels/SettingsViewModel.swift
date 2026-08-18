import Foundation
import Combine
import ServiceManagement

class SettingsViewModel: ObservableObject {
    @Published var maxHistoryCount: Int = 100
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update Launch at Login: \(error)")
                // Revert state if it failed
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}