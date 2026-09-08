import Foundation
import Security
import AinkradHostRuntime

/// `SecretStore` backed by the macOS Keychain (generic password items).
/// Each secret is one item keyed by `(service, account=id)`.
///
/// **Items live in the DATA PROTECTION keychain, not the legacy file-based one.**
/// That is the whole reason `kSecUseDataProtectionKeychain` appears in every
/// query below, and it is not a style choice. Legacy `login.keychain-db` items
/// carry an ACL naming the exact *binaries* allowed to read them, matched by
/// code-signing identity. Ainkrad exists as three differently signed binaries on
/// a developer's machine at once — the Debug build, the Release build, and the
/// Developer-ID app in /Applications — and every `xcodebuild` mints a fresh
/// cdhash for the first two. So each build was a stranger to the ACL and macOS
/// put up the "Ainkrad wants to use your confidential information" password
/// panel; "Always Allow" authorized only that one binary and the next compile
/// invalidated it. The data-protection keychain has no per-binary ACL: access is
/// decided by the signature's Team ID plus the access group from the
/// `keychain-access-groups` entitlement (see config/Ainkrad.entitlements), both
/// identical across all three builds. Never drop the flag to "simplify" this.
///
/// The access group is left implicit: with a single entry in the entitlement,
/// items are filed under it automatically, so the Team-ID prefix never has to be
/// hardcoded or recovered at runtime.
///
/// Secrets written by older releases are still in the legacy keychain, and are
/// adopted one at a time by `adoptLegacySecret(for:)` on first read. Read that
/// comment before making the move eager again.
final class KeychainSecretStore: SecretStore {
    private let service: String

    /// False when this process cannot reach the data-protection keychain at all,
    /// which happens only when the running binary is signed without the
    /// `keychain-access-groups` entitlement (an ad-hoc or unsigned build, or a
    /// SwiftPM `swift test` runner). Rather than fail every read, such a process
    /// falls back to the legacy keychain and gets the old prompt behaviour —
    /// annoying but working. Releases cannot land in this state: the entitlement
    /// is asserted on the signed artifact by `scripts/release.sh`.
    ///
    /// Not private: the legacy-adoption tests have to know which keychain they are
    /// actually exercising, because the answer depends on how the test runner
    /// happened to be signed and asserting the wrong one would make the suite
    /// pass or fail for reasons that have nothing to do with this code.
    let usesDataProtection: Bool

    init(service: String = Bundle.main.bundleIdentifier ?? "com.ainkrad.app") {
        self.service = service
        self.usesDataProtection = Self.dataProtectionKeychainIsUsable()
    }

    private func baseQuery(for id: String) -> [String: Any] {
        var query = Self.legacyQuery(service: service, id: id)
        if usesDataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    func secret(for id: String) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecSuccess && status != errSecItemNotFound {
                Log.persistence.error("Keychain read failed for \(id, privacy: .public): \(status)")
            }
            return status == errSecItemNotFound ? adoptLegacySecret(for: id) : nil
        }
        return value
    }

    func setSecret(_ value: String?, for id: String) {
        guard let value else {
            SecItemDelete(baseQuery(for: id) as CFDictionary)
            // Also clear any legacy copy. Without this, `secret(for:)` would
            // adopt the old value straight back out of the legacy keychain and
            // a deleted credential would return from the dead.
            if usesDataProtection {
                SecItemDelete(Self.legacyQuery(service: service, id: id) as CFDictionary)
            }
            return
        }
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: id) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = baseQuery(for: id)
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Log.persistence.error("Keychain add failed for \(id, privacy: .public): \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            Log.persistence.error("Keychain update failed for \(id, privacy: .public): \(updateStatus)")
        }
    }

    // MARK: - Legacy keychain

    /// A query against the LEGACY file-based keychain — i.e. the same query
    /// minus `kSecUseDataProtectionKeychain`. The two keychains are separate
    /// namespaces, so an item written to one is invisible to the other.
    private static func legacyQuery(service: String, id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            // Explicitly FALSE, not merely omitted. Omitting the key does not
            // reliably mean "legacy" once the process has an access group: the
            // adoption's delete then reached into the data-protection keychain
            // and removed the copy it had just written, leaving the secret gone
            // from both. Caught by `adoptsOnFirstRead`.
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    /// Whether this process may use the data-protection keychain, answered from
    /// the running binary's own signature.
    ///
    /// Do NOT try to answer this by probing the keychain: a data-protection READ
    /// from an unentitled process returns a perfectly ordinary
    /// `errSecItemNotFound`, so a read probe reports success and every later
    /// write then fails with `errSecMissingEntitlement` (-34018) — silently
    /// losing secrets. Only writes are gated, so the signature is the only
    /// honest thing to ask. (Found by doing exactly that: the probe passed and
    /// the round-trip tests failed.)
    private static func dataProtectionKeychainIsUsable() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        // Either entitlement establishes an access group for the process, which
        // is what the data-protection keychain files items under.
        let keys = ["keychain-access-groups", "com.apple.security.app-sandbox"]
        let usable = keys.contains { SecTaskCopyValueForEntitlement(task, $0 as CFString, nil) != nil }
        if !usable {
            Log.persistence.error(
                "No keychain access group entitlement; using the legacy keychain, which prompts per binary.")
        }
        return usable
    }

    /// Moves ONE secret out of the legacy keychain, at the moment something
    /// actually asks for it, and returns it.
    ///
    /// Deliberately lazy, and that is the second design here rather than the
    /// first. The original version enumerated the whole service at launch and
    /// read every item, which raised one login-password panel PER STORED SECRET
    /// — over ten in a row on a real vault, because reading an item's data is
    /// exactly what the legacy ACL guards. Migrating on demand means at most one
    /// prompt, for a secret the user is actively using, at a moment when the
    /// reason for it is obvious.
    ///
    /// The legacy item is deleted only after a successful read, so a denied or
    /// failed prompt costs nothing: the secret stays where it is and the next
    /// attempt can still find it. There is no "migration done" marker to get
    /// wrong — `setSecret(nil:)` clears both keychains, which is what a marker
    /// was there to compensate for.
    private func adoptLegacySecret(for id: String) -> String? {
        guard usesDataProtection, let value = legacySecret(for: id) else { return nil }
        setSecret(value, for: id)
        SecItemDelete(Self.legacyQuery(service: service, id: id) as CFDictionary)
        return value
    }

    private func legacySecret(for id: String) -> String? {
        var query = Self.legacyQuery(service: service, id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
