import AinkradAppKit
import Foundation

/// One-time move of Terminal's settings from the host-global document store
/// (pre-4a) into Terminal's app-scoped store. Type-free: the `TerminalSettings`
/// type now lives in the Terminal plugin, so this copies the raw payload bytes
/// keyed by the well-known documentID. Runs once (UserDefaults-gated); never
/// touches secrets; never overwrites an existing scoped doc.
enum TerminalSettingsMigration {
    static let flagKey = "terminal.settings.migratedToScopedStore"
    static let documentID = "terminal-settings"

    static func runIfNeeded(
        legacyRawPayload: (String) -> Data?,
        scoped: PluginDocumentStore, defaults: UserDefaults
    ) {
        guard !defaults.bool(forKey: flagKey) else { return }
        defer { defaults.set(true, forKey: flagKey) }
        guard scoped.data(forKey: documentID) == nil,
            let bytes = legacyRawPayload(documentID)
        else { return }
        scoped.setData(bytes, forKey: documentID)
    }
}
