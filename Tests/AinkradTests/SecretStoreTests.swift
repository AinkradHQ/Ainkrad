import Testing
import Foundation
import Security
@testable import Ainkrad
import AinkradHostRuntime

@Suite("InMemorySecretStore")
struct InMemorySecretStoreTests {
    @Test("returns nil for an unknown id")
    func nilWhenUnknown() {
        #expect(InMemorySecretStore().secret(for: "x") == nil)
    }

    @Test("set then get round-trips, and nil deletes")
    func roundTripAndDelete() {
        let store = InMemorySecretStore()
        store.setSecret("token", for: "x")
        #expect(store.secret(for: "x") == "token")
        store.setSecret(nil, for: "x")
        #expect(store.secret(for: "x") == nil)
    }
}

/// Exercises the real Keychain. Requires a logged-in user session (local
/// `make test`); uses a unique service so runs never collide, and cleans up.
@Suite("KeychainSecretStore")
final class KeychainSecretStoreTests {
    let service = "com.ainkrad.tests.keychain.\(UUID().uuidString)"
    var store: KeychainSecretStore { KeychainSecretStore(service: service) }

    deinit {
        let s = KeychainSecretStore(service: service)
        for id in ["a", "b"] { s.setSecret(nil, for: id) }
    }

    @Test("returns nil for an unknown id")
    func nilWhenUnknown() {
        #expect(store.secret(for: "a") == nil)
    }

    @Test("set then get round-trips")
    func roundTrips() {
        store.setSecret("sk-123", for: "a")
        #expect(store.secret(for: "a") == "sk-123")
    }

    @Test("setting an existing id updates it")
    func updatesExisting() {
        store.setSecret("first", for: "b")
        store.setSecret("second", for: "b")
        #expect(store.secret(for: "b") == "second")
    }

    @Test("setting nil deletes the secret")
    func nilDeletes() {
        store.setSecret("gone", for: "a")
        store.setSecret(nil, for: "a")
        #expect(store.secret(for: "a") == nil)
    }
}



/// The legacy-keychain escape hatch: secrets written by older releases live in
/// the file-based login keychain, and the store has to adopt them on demand or
/// every saved API key vanishes on upgrade.
@Suite("KeychainSecretStore legacy adoption")
final class KeychainSecretStoreLegacyTests {
    let service = "com.ainkrad.tests.keychain.legacy.\(UUID().uuidString)"

    deinit {
        KeychainSecretStore(service: service).setSecret(nil, for: "a")
        for useDataProtection in [true, false] {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: useDataProtection,
            ] as CFDictionary)
        }
    }

    /// Writes straight into the legacy keychain, bypassing the store — the
    /// state an upgrading user is actually in. The explicit `false` matters:
    /// an entitled process otherwise lands in the data-protection keychain and
    /// the test proves nothing.
    @discardableResult
    private func addLegacyItem(_ value: String, id: String) -> OSStatus {
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: Data(value.utf8),
            kSecUseDataProtectionKeychain as String: false,
        ] as CFDictionary, nil)
    }

    private func legacyItemExists(id: String) -> Bool {
        SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecUseDataProtectionKeychain as String: false,
        ] as CFDictionary, nil) == errSecSuccess
    }

    @Test("a secret written by an older release is adopted on first read")
    func adoptsOnFirstRead() {
        let addStatus = addLegacyItem("sk-legacy", id: "a")
        // Guard the setup itself: a silently failed add would let the
        // assertions below pass against an empty keychain.
        #expect(addStatus == errSecSuccess, "legacy add status \(addStatus)")
        #expect(legacyItemExists(id: "a"), "legacy item missing before the read")

        let store = KeychainSecretStore(service: service)

        let adopted = store.secret(for: "a")
        #expect(adopted == "sk-legacy",
                "adopted=\(String(describing: adopted)) dataProtection=\(store.usesDataProtection)")
        // The legacy item is consumed only when there is somewhere to move it
        // to. An unentitled runner has no second keychain and keeps reading the
        // item in place; asserting it disappeared would be asserting data loss.
        #expect(legacyItemExists(id: "a") == !store.usesDataProtection)
    }

    @Test("a deleted secret does not come back from the legacy keychain")
    func deletionClearsBothKeychains() {
        addLegacyItem("sk-legacy", id: "a")
        let store = KeychainSecretStore(service: service)
        #expect(store.secret(for: "a") == "sk-legacy")

        store.setSecret(nil, for: "a")

        #expect(store.secret(for: "a") == nil)
        #expect(legacyItemExists(id: "a") == false)
    }

    @Test("nothing is read from the legacy keychain until a secret is asked for")
    func constructionAlonePromptsForNothing() {
        addLegacyItem("sk-legacy", id: "a")

        _ = KeychainSecretStore(service: service)

        // Constructing the store must not touch item DATA — that read is what
        // raises the login-password panel, and doing it for every stored secret
        // at launch is the bug this design replaced.
        #expect(legacyItemExists(id: "a"))
    }
}
