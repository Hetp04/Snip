import Foundation
import Security

/// Stores user-provided provider credentials outside the app bundle and
/// UserDefaults. A shipped app must never contain the developer's API key.
enum SecureCredentialStore {
    private nonisolated static let service = "Her.hetpaste.credentials"
    private nonisolated static let openRouterAccount = "openrouter-api-key"

    nonisolated static var openRouterAPIKey: String {
        (try? value(for: openRouterAccount)) ?? ""
    }

    nonisolated static func setOpenRouterAPIKey(_ value: String) throws {
        try set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: openRouterAccount)
    }

    private nonisolated static func value(for account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return value
    }

    private nonisolated static func set(_ value: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            return
        }
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(create as CFDictionary, nil)
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if updateStatus != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
    }
}
