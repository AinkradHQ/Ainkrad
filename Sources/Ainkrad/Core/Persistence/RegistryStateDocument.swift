import AinkradHostRuntime
import Foundation

/// Persisted enable/disable overrides for Built-in Apps, keyed by app id.
/// A wrapper so the registry's `[String: Bool]` can be a versioned document.
struct RegistryStateDocument: PersistableDocument {
    static let documentID = "registry-enabled-state"
    static let currentSchemaVersion = 2

    /// v1 → v2: the 2026-08-02 app rename, so an app the user disabled stays
    /// disabled rather than silently re-enabling under its new id.
    static let migrators: [DocumentMigrator] = [
        DocumentMigrator(from: 1) { payload in
            guard case .object(var root) = payload,
                case .object(let enabled)? = root["enabled"]
            else { return payload }
            root["enabled"] = .object(AppIDRenames.rekeyed(enabled))
            return .object(root)
        }
    ]

    var enabled: [String: Bool] = [:]
}
