import AinkradHostRuntime
import Foundation

/// What is installed and at which version — the source of truth for update
/// detection and uninstall. (Enabled/disabled state stays in RegistryStateDocument.)
struct InstalledPluginsDocument: PersistableDocument {
    static let documentID = "installed-plugins"
    static let currentSchemaVersion = 2

    /// v1 → v2: the 2026-08-02 app rename. An installed `terminal` bundle is the
    /// same app as `rune`; without this, `PluginLoader` dedups by appID, treats
    /// them as unrelated apps, and the user ends up with BOTH.
    ///
    /// `sourceRepo` is left pointing at the old path deliberately — GitHub
    /// 301-redirects a renamed repo, and the next catalog refresh overwrites the
    /// field with the new one anyway.
    static let migrators: [DocumentMigrator] = [
        DocumentMigrator(from: 1) { payload in
            guard case .object(var root) = payload,
                case .object(let installed)? = root["installed"]
            else { return payload }
            root["installed"] = .object(AppIDRenames.rekeyed(installed))
            return .object(root)
        }
    ]

    struct Entry: Codable, Equatable {
        let version: String
        let sourceRepo: String
    }
    var installed: [String: Entry] = [:]  // keyed by appID
}
