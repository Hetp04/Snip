import Foundation
struct UserSettings: Codable {
    var maxHistoryCount: Int = 100
    var launchAtLogin: Bool = false
    var soundEffectsEnabled: Bool = true
    var syncEnabled: Bool = false
}