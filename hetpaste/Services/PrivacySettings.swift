import Combine
import Foundation

/// External AI can improve semantic search, but it may send clipboard-derived
/// text to a configured provider. Keep it disabled until the user opts in.
@MainActor
final class PrivacySettings: ObservableObject {
    static let shared = PrivacySettings()
    private let key = "privacy.allowsExternalAI"
    private let externalAIDisabledMigrationKey = "privacy.external-ai-disabled-v1"
    @Published var allowsExternalAI: Bool {
        didSet { UserDefaults.standard.set(allowsExternalAI, forKey: key) }
    }
    private init() {
        let defaults = UserDefaults.standard

        // Disable external embedding requests once for existing installs while the
        // CloudKit rollout is being stabilized. Users can explicitly re-enable it
        // later from Settings.
        if !defaults.bool(forKey: externalAIDisabledMigrationKey) {
            defaults.set(false, forKey: key)
            defaults.set(true, forKey: externalAIDisabledMigrationKey)
        }

        allowsExternalAI = defaults.bool(forKey: key)
    }
}
