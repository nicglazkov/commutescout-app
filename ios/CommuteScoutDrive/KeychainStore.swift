import Foundation
import Security

/// Small strings that must not sit in UserDefaults, such as a private
/// plugin's bearer token: one generic-password item per key in the app's
/// own keychain service, readable after the first unlock so polling
/// keeps working while the phone is in a pocket. Never synced or backed up.
enum KeychainStore {
    private static let service = "com.commutescout.drive.secrets"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores the value, replacing what was there; nil removes the item.
    static func set(_ value: String?, for key: String) {
        guard let value, let data = value.data(using: .utf8) else { remove(key); return }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(key) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(key)
            attrs.forEach { q[$0.key] = $0.value }
            _ = SecItemAdd(q as CFDictionary, nil)
        }
    }

    static func remove(_ key: String) {
        _ = SecItemDelete(query(key) as CFDictionary)
    }
}
