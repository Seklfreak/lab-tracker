import Foundation
import Security

/// Tiny Keychain wrapper for the OIDC tokens (more appropriate than UserDefaults
/// for credentials). Keyed by a string account under one service.
enum Keychain {
    private static let service = "dev.winktech.labtracker"

    /// Writes (or clears, for nil) one item, replacing any existing value in
    /// place rather than deleting it first.
    ///
    /// The delete-then-add this replaces left a window in which the item did
    /// not exist at all. That is survivable for most values and fatal for a
    /// rotating refresh token: the provider voids the old token the moment it
    /// issues the new one, so a process killed inside that window — routine
    /// for one iOS woke in the background — comes back with neither, and no
    /// way to restore the session short of a manual sign-in.
    static func set(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, let data = value.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}
