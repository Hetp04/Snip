import Foundation
import Combine
class SettingsViewModel: ObservableObject {
    @Published var maxHistoryCount: Int = 100
    @Published var launchAtLogin: Bool = false
}