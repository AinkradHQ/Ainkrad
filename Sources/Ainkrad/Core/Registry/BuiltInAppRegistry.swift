import AinkradHostRuntime
import Observation

/// Single source of truth for which apps exist and are enabled. Hybrid: apps
/// are installed once after `AppEnvironment` exists, mixing compiled-in apps
/// with dynamically-loaded plugin bundles.
@MainActor
@Observable
final class BuiltInAppRegistry {
    private var registeredApps: [RegisteredApp] = []
    private let persistence: PersistenceStore
    private var enabledOverrides: [String: Bool]
    private(set) var loadFailures: [PluginLoadFailure] = []

    /// Host-side follow-up to an app's own `teardown`, run on the same seam:
    /// anything the HOST caches per app id and must drop when that app goes
    /// away. Bootstrap points it at `AppServerActivator.evict`, whose memoized
    /// MCP server would otherwise outlive the instance it was built over. A
    /// closure, not a direct reference, so the registry gains no dependency on
    /// the MCP subsystem's shape.
    @ObservationIgnored var onAppTornDown: ((String) -> Void)?

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.enabledOverrides = persistence.load(RegistryStateDocument.self)?.enabled ?? [:]
    }

    /// Installs the resolved app set. Built-in apps win id conflicts with
    /// plugins. Called once during bootstrap after the environment exists.
    func install(builtIn: [RegisteredApp], loaded: [RegisteredApp] = [], failures: [PluginLoadFailure] = []) {
        loadFailures = failures
        var byID: [String: RegisteredApp] = [:]
        var order: [String] = []
        for app in builtIn where byID[app.id] == nil {
            byID[app.id] = app
            order.append(app.id)
        }
        for app in loaded {
            if byID[app.id] != nil {
                Log.registry.error("Plugin id conflict \(app.id, privacy: .public) — built-in wins, plugin skipped")
                continue
            }
            byID[app.id] = app
            order.append(app.id)
        }
        registeredApps = order.compactMap { byID[$0] }
    }

    /// Adds a freshly-installed plugin to the live app list (or replaces the
    /// existing plugin with the same id). Refuses to shadow a built-in id.
    func register(_ app: RegisteredApp) {
        if let existing = registeredApps.first(where: { $0.id == app.id }), existing.source == .builtIn {
            Log.registry.error("register: \(app.id, privacy: .public) is a built-in — plugin ignored")
            return
        }
        registeredApps.removeAll { $0.id == app.id }
        registeredApps.append(app)
    }

    /// Removes a plugin from the live app list. Built-in ids are ignored.
    /// (An already-loaded dylib cannot be unloaded; this only hides it.)
    func deregister(id: String) {
        guard let app = registeredApps.first(where: { $0.id == id }), app.source != .builtIn else { return }
        // Tell the plugin it is done before dropping it. Without this, a plugin
        // removed by the user kept its watchers, timers, open databases and
        // file descriptors alive for the rest of the process — the SDK simply
        // never had a way to say "you're finished". Opt-in and best-effort: a
        // generation-7 plugin has no teardown and this is a no-op.
        app.teardown?()
        onAppTornDown?(id)
        registeredApps.removeAll { $0.id == id }
    }

    var allApps: [RegisteredApp] { registeredApps }

    var enabledApps: [RegisteredApp] { registeredApps.filter { isEnabled($0.id) } }

    func isEnabled(_ id: String) -> Bool {
        if let override = enabledOverrides[id] { return override }
        return registeredApps.first(where: { $0.id == id })?.isEnabledByDefault ?? false
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        enabledOverrides[id] = enabled
        persistence.save(RegistryStateDocument(enabled: enabledOverrides))
        Log.registry.info("App \(id, privacy: .public) \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
