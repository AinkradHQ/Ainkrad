import AinkradHostRuntime
import Foundation
import Observation

/// Per-kind privacy toggles for `AgentContextService` — persisted as explicit
/// opt-outs only. A missing key means "enabled", so unknown/future kinds
/// (and legacy payloads) default to on with no migration needed — same
/// idiom as `GlobalSettings.soundEventEnabled` / `GeneralSettingsStore`.
struct AgentContextSettings: PersistableDocument {
    static let documentID = "agent-context-settings"
    /// Explicit opt-outs, keyed by `AgentContextSnapshot.kind`. A missing key
    /// means the kind is enabled.
    var kindEnabled: [String: Bool] = [:]

    init(kindEnabled: [String: Bool] = [:]) {
        self.kindEnabled = kindEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kindEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .kindEnabled) ?? [:]
    }
}

/// Owns Settings → privacy toggles for what workspace context
/// `AgentContextService` is allowed to include (e.g. terminal buffer, git
/// status). Load/mutate/save follows the same pattern as
/// `GeneralSettingsStore`.
@MainActor
@Observable
final class AgentContextSettingsStore {
    private(set) var kindEnabled: [String: Bool]
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(AgentContextSettings.self) ?? AgentContextSettings()
        self.kindEnabled = settings.kindEnabled
    }

    /// Defaults to enabled for every kind, known or unknown — only explicit
    /// opt-outs are ever persisted.
    func isEnabled(kind: String) -> Bool {
        kindEnabled[kind] ?? true
    }

    func setEnabled(_ isOn: Bool, for kind: String) {
        // Only explicit opt-outs are stored; enabling removes the key so the
        // persisted doc stays minimal and future kinds default to enabled.
        kindEnabled[kind] = isOn ? nil : false
        var settings = persistence.load(AgentContextSettings.self) ?? AgentContextSettings()
        settings.kindEnabled = kindEnabled
        persistence.save(settings)
    }
}
