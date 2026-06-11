import Foundation
import Security

/// Token persistence for the GitLab access token.
///
/// Historically this used the macOS Keychain, but ad-hoc signed builds receive
/// a new code-signing identity each rebuild and macOS denies access to keychain
/// items created by a previous signature — colleagues installing a new DMG would
/// lose their token. For an internally distributed tool the simpler trade-off is
/// to store the token in UserDefaults (which is keyed by bundle id and survives
/// reinstalls), and run a one-shot migration that pulls any pre-existing
/// keychain value forward so existing users don't have to re-enter it.
enum KeychainService {
    private static let userDefaultsKey = "com.status-hub.gitlab.accessToken"
    private static let migrationFlagKey = "com.status-hub.gitlab.keychainMigrationDone"
    private static let legacyService = "com.gitlab-monitor"
    private static let legacyAccount = "access-token"

    static func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        }
    }

    static func loadToken() -> String? {
        migrateLegacyKeychainTokenIfNeeded()
        if let token = UserDefaults.standard.string(forKey: userDefaultsKey),
           !token.isEmpty {
            return token
        }
        return nil
    }

    static func deleteToken() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        deleteLegacyKeychainItem()
    }

    // MARK: - One-shot migration from legacy Keychain storage

    private static func migrateLegacyKeychainTokenIfNeeded() {
        if UserDefaults.standard.bool(forKey: migrationFlagKey) { return }
        defer { UserDefaults.standard.set(true, forKey: migrationFlagKey) }

        if UserDefaults.standard.string(forKey: userDefaultsKey)?.isEmpty == false {
            // Already have a token in UserDefaults — nothing to migrate.
            return
        }

        if let legacy = readLegacyKeychainItem(), !legacy.isEmpty {
            UserDefaults.standard.set(legacy, forKey: userDefaultsKey)
            deleteLegacyKeychainItem()
        }
    }

    private static func readLegacyKeychainItem() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacyKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
