import AinkradAppKit

/// Per-app `PluginAppLauncher` handed to one plugin's HostServices. Forwards to
/// the shared hub, tagged with this app's id (mirrors `HostContextRegistry`).
///
/// Also conforms to generation 8's `PluginAppLauncherResult`, so a caller can
/// find out whether the app actually opened. `open(appID:payload:)` returns
/// `Void`, which meant Leyline's "connect" button looked identical whether
/// Terminal launched or was not installed at all — RC-5 (failure recorded,
/// never surfaced) reproduced at the plugin boundary.
///
/// The richer method is on a SEPARATE protocol, discovered by cast, rather than
/// added to `PluginAppLauncher` — the generation-8 freeze rule, since an added
/// protocol requirement is the one change library evolution does not cover.
@MainActor
public struct HostAppLauncher: PluginAppLauncher, PluginAppLauncherResult {
    let appID: String
    unowned let hub: PluginLaunchHub

    public init(appID: String, hub: PluginLaunchHub) {
        self.appID = appID
        self.hub = hub
    }

    public func open(appID: String, payload: String?) {
        _ = openReportingOutcome(appID: appID, payload: payload)
    }

    public func openReportingOutcome(appID requested: String, payload: String?) -> PluginLaunchOutcome {
        // Resolve a retired app id to its replacement. An INSTALLED plugin
        // carries whatever id it was built against: Leyline v0.6.1 ships
        // `open(appID:)` with "terminal", and after the v0.16.0 rename that returns
        // `.unknownApp` — its connect button silently does nothing. Aliasing
        // here fixes every already-installed plugin at once, rather than
        // requiring each one to ship an update first.
        let target = AppIDRenames.map[requested] ?? requested

        // Ask the hub whether the target is actually openable BEFORE enqueuing
        // a payload for it — a payload left pending for an app that never
        // opens is a leak that also mis-fires if that app is installed later.
        switch hub.availability(of: target) {
        case .unknown:
            return .unknownApp(target)
        case .disabled:
            return .disabled(target)
        case .available:
            hub.enqueue(target: target, payload: payload)
            hub.requestOpen(target)
            return .opened
        }
    }

    public func takePendingLaunch() -> String? { hub.takePending(for: appID) }
}

/// Lets a plugin ask whether another app is installed and enabled (`PluginAppLauncher.appAvailability`), e.g.
/// Grimoire's "↗ Open" when Forge is missing. Same alias resolution and availability test as opening.
extension HostAppLauncher: PluginAppAvailability {
    public func isAppAvailable(appID requested: String) -> Bool {
        let target = AppIDRenames.map[requested] ?? requested
        if case .available = hub.availability(of: target) { return true }
        return false
    }
}
