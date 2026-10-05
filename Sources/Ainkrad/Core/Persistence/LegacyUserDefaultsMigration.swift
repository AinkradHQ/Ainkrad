import Foundation
import AinkradHostRuntime

/// One-time import of M1's `UserDefaults`-backed settings into the new
/// file-based document store. Runs at bootstrap before the domain stores are
/// constructed; a marker document guarantees it happens exactly once. The
/// legacy `UserDefaults` values are left in place (harmless, and a safety net).
enum LegacyUserDefaultsMigration {
    struct LegacyImportMarker: PersistableDocument {
        static let documentID = "legacy-import-marker"
        var didImport: Bool = false
    }

    /// True in a DEBUG fixture launch. The Debug host shares the daily host's UserDefaults
    /// domain (same bundle id), so importing would pull the real settings and workspaces
    /// into the fixture vault.
    static var isFixtureLaunch: Bool {
        #if DEBUG
        return debugFixtureRoots != nil
        #else
        return false
        #endif
    }

    static func runIfNeeded(persistence: PersistenceStore, defaults: UserDefaults = .standard,
                            isFixtureLaunch: Bool = LegacyUserDefaultsMigration.isFixtureLaunch) {
        if isFixtureLaunch { return }
        if persistence.load(LegacyImportMarker.self)?.didImport == true { return }

        let decoder = JSONDecoder()  // M1 wrote plain JSON with no date strategy

        if let data = defaults.data(forKey: "global-settings"),
           let value = try? decoder.decode(GlobalSettings.self, from: data) {
            persistence.save(value)
        }
        if let data = defaults.data(forKey: "registry-enabled-state"),
           let value = try? decoder.decode([String: Bool].self, from: data) {
            persistence.save(RegistryStateDocument(enabled: value))
        }
        if let data = defaults.data(forKey: "workspace-layout-v1"),
           let value = try? decoder.decode(LayoutStateSnapshot.self, from: data) {
            persistence.save(value)
        }
        // Terminal's settings type no longer lives in the host (it moved to
        // the AinkradTerminal plugin), so this copies the raw JSON payload
        // rather than decoding into a concrete type. `TerminalSettingsMigration`
        // later moves this host-global copy into the plugin's scoped store.
        if let data = defaults.data(forKey: "terminal-settings"),
           let value = try? decoder.decode(JSONValue.self, from: data) {
            (persistence as? FileDocumentStore)?.saveRawPayload(value, forID: "terminal-settings", schemaVersion: 1)
        }

        // Marker is set even on a partial import (a key that fails to decode is
        // skipped and not retried); acceptable because the legacy UserDefaults
        // values are left in place for manual recovery.
        persistence.save(LegacyImportMarker(didImport: true))
        Log.persistence.info("Imported legacy UserDefaults settings into file documents")
    }
}
