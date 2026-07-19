import Foundation
import Security

/// Minimal Keychain wrapper for provider API keys.
/// Account = `ProviderAccount.id`; the DB never stores secrets.
///
/// Items live in the **data-protection keychain** (`kSecUseDataProtectionKeychain`),
/// where access is granted by the app's code-signing entitlement — no per-binary
/// ACLs, so the user is never shown a keychain password dialog, including after
/// rebuilds. Items created by older builds in the legacy login keychain are
/// migrated on first read (one final unlock), then the legacy copy is deleted.
public enum Keychain {
    public static let service = "com.jarvis.app.keys"

    public enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    /// Returned when the build lacks an application identifier (ad-hoc signing);
    /// fall back to the legacy login keychain so the app still works.
    private static let missingEntitlement: OSStatus = -34018 // errSecMissingEntitlement

    private static func query(account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    // MARK: - Set

    public static func set(_ value: String, account: String) throws {
        do {
            try set(value, account: account, dataProtection: true)
        } catch KeychainError.unexpectedStatus(missingEntitlement) {
            try set(value, account: account, dataProtection: false)
        }
    }

    private static func set(_ value: String, account: String, dataProtection: Bool) throws {
        let data = Data(value.utf8)
        let query = query(account: account, dataProtection: dataProtection)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            if dataProtection {
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else {
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        }
    }

    // MARK: - Get

    public static func get(account: String) throws -> String? {
        var query = query(account: account, dataProtection: true)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        case missingEntitlement:
            return try legacyGet(account: account)
        case errSecItemNotFound:
            // Migrate any legacy login-keychain item written by older builds
            // (the one read that can still show a system dialog). Delete the
            // legacy copy only once the new write verifiably succeeded.
            guard let legacy = try legacyGet(account: account) else { return nil }
            if (try? set(legacy, account: account, dataProtection: true)) != nil {
                SecItemDelete(Self.query(account: account, dataProtection: false) as CFDictionary)
            }
            return legacy
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func legacyGet(account: String) throws -> String? {
        var query = query(account: account, dataProtection: false)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    public static func delete(account: String) throws {
        for dataProtection in [true, false] {
            let status = SecItemDelete(query(account: account, dataProtection: dataProtection) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound || status == missingEntitlement else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }
}
