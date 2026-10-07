import AinkradAppKit
import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/AppServerActivator.swift
import Foundation

/// Why an app's MCP server could not be reached. Distinct cases so the failure
/// text the model sees names an actionable cause instead of "something failed".
enum AppDispatchFailure: Error, Equatable {
    /// No app with that id has an MCP server (not installed, or doesn't conform).
    case notInstalled(String)
    /// Registered but switched off by the user.
    case disabled(String)
    /// Launch was requested but the app never came up inside the timeout.
    case launchTimedOut(String)
}

/// Owns the app-side MCP servers and the lifecycle around reaching them.
///
/// An app's server object can exist while the app is closed, but its handlers
/// generally hold a bridge that is nil with no live shell (see GitMage's
/// `contextBridge`), so a call to a closed app must open it FIRST. That is the
/// whole reason this type exists — `InProcessTransport` stays a dumb pipe.
///
/// Collaborators arrive as closures rather than as `PluginLaunchHub` + the app
/// registry so this is testable without a host bootstrap; `AppEnvironment`
/// supplies hub-backed closures.
@MainActor
final class AppServerActivator {
    /// Resolves an app's server on first use rather than at construction.
    ///
    /// A closure, not a stored dictionary, for the same reason `isAppOpen` /
    /// `requestOpen` / `availability` are closures: this type must not bake in
    /// bootstrap's ordering. The app registry is EMPTY when the activator is
    /// built (`bootstrapExecutionAndTools`) and only gets populated later, by
    /// `registry.install(...)` in `finalizeBootstrap` — an eagerly-captured
    /// dictionary would therefore always be empty. It also means an app
    /// installed after launch is picked up without rebuilding anything.
    private let serverFor: (String) -> MCPAppServer?
    /// Memoizes resolved servers so each app's server object — and therefore
    /// its live state — is built exactly once for the process lifetime.
    private var cache: [String: MCPAppServer] = [:]
    private let isAppOpen: (String) -> Bool
    private let requestOpen: (String) -> Void
    private let availability: (String) -> PluginLaunchHub.Availability
    private let launchTimeout: Duration
    private let onLaunch: ((String) -> Void)?
    /// How often to re-check `isAppOpen` while waiting for a launch.
    private let pollInterval: Duration = .milliseconds(50)

    /// The only JSON-RPC methods that CAN justify force-opening a closed app.
    ///
    /// `MCPAppServer.handle` answers `initialize`, `tools/list` and
    /// `resources/list` purely from registration-time metadata (names,
    /// descriptions, schemas, uris) — no bridge, no live view model, so no
    /// shell is needed. Only `tools/call` and `resources/read` reach an
    /// app-supplied handler/provider closure, which is where a nil context
    /// bridge on a closed app could bite. Opening for everything would mean
    /// `MCPServerRegistry.connectEnabled()`'s launch-time `initialize` popped
    /// open EVERY MCP-publishing app on every launch, unasked.
    ///
    /// Being in this set is NECESSARY but no longer SUFFICIENT: the method gate
    /// alone opened the app for every tool call, so asking the assistant to
    /// create a Lore note popped Lore's window open. A tool call is background
    /// work; the per-tool `requiresLiveApp` closure below makes the real call.
    private static let methodsRequiringLiveApp: Set<String> = ["tools/call", "resources/read"]

    /// Does this specific tool/resource need the app's window on screen?
    /// Called with the app id, the JSON-RPC method, and the target's name
    /// (`params.name` for `tools/call`, `params.uri` for `resources/read`).
    ///
    /// A closure for the same reason `isAppOpen`/`requestOpen`/`availability`
    /// are: the answer comes from the MCP registry's discovered descriptors,
    /// which do not exist yet when this type is built at bootstrap, and it keeps
    /// the activator testable without a host.
    private let requiresLiveApp: (String, String, String) -> Bool

    init(
        serverFor: @escaping (String) -> MCPAppServer?,
        isAppOpen: @escaping (String) -> Bool,
        requestOpen: @escaping (String) -> Void,
        availability: @escaping (String) -> PluginLaunchHub.Availability,
        // Defaults to "nothing needs the window", which is the behaviour we
        // want when no app declares anything: tool calls run in the background.
        requiresLiveApp: @escaping (String, String, String) -> Bool = { _, _, _ in false },
        launchTimeout: Duration = .seconds(5),
        onLaunch: ((String) -> Void)? = nil
    ) {
        self.serverFor = serverFor
        self.isAppOpen = isAppOpen
        self.requestOpen = requestOpen
        self.availability = availability
        self.requiresLiveApp = requiresLiveApp
        self.launchTimeout = launchTimeout
        self.onLaunch = onLaunch
    }

    /// A fixed set of servers — the shape tests and any caller that already
    /// holds every server use. Wraps the dictionary in a provider closure so
    /// there is only one lookup path.
    convenience init(
        servers: [String: MCPAppServer],
        isAppOpen: @escaping (String) -> Bool,
        requestOpen: @escaping (String) -> Void,
        availability: @escaping (String) -> PluginLaunchHub.Availability,
        requiresLiveApp: @escaping (String, String, String) -> Bool = { _, _, _ in false },
        launchTimeout: Duration = .seconds(5),
        onLaunch: ((String) -> Void)? = nil
    ) {
        self.init(
            serverFor: { servers[$0] }, isAppOpen: isAppOpen, requestOpen: requestOpen,
            availability: availability, requiresLiveApp: requiresLiveApp,
            launchTimeout: launchTimeout, onLaunch: onLaunch)
    }

    /// Resolves — and on first success caches — this app's server. Every read
    /// of a server goes through here so a server is never built twice.
    private func server(for appID: String) -> MCPAppServer? {
        if let cached = cache[appID] { return cached }
        guard let server = serverFor(appID) else { return nil }
        cache[appID] = server
        return server
    }

    /// True when this app publishes an MCP server at all.
    func hasServer(appID: String) -> Bool { server(for: appID) != nil }

    /// Drops this app's cached server, so the next dispatch resolves a fresh one.
    ///
    /// Called when the app is torn down (`BuiltInAppRegistry.deregister`,
    /// right after `RegisteredApp.teardown`). Without it the memoized server
    /// outlives the instance it was built over: an app that tears its own
    /// instance state down on close (Git Mage's `GitMageRuntime.teardown`
    /// removes its server) would be driven through a DETACHED server holding
    /// the closed instance's `HostServices` — the case the SDK's
    /// `makeMCPServer` doc warns about, and a pin on that instance for the rest
    /// of the process, which is exactly the leak `AinkradAppTeardown` exists to
    /// close.
    func evict(appID: String) { cache[appID] = nil }

    /// Sends one JSON-RPC message to the app's server, opening the app first if
    /// the message needs a live shell and the app isn't already open. Returns
    /// the raw reply, or an empty string when the message was a notification.
    func dispatch(appID: String, message: String) async throws -> String {
        guard let server = server(for: appID) else { throw AppDispatchFailure.notInstalled(appID) }

        if needsLiveApp(appID: appID, message: message), !isAppOpen(appID) {
            switch availability(appID) {
            case .unknown: throw AppDispatchFailure.notInstalled(appID)
            case .disabled: throw AppDispatchFailure.disabled(appID)
            case .available: break
            }
            requestOpen(appID)
            onLaunch?(appID)
            try await waitUntilOpen(appID)
        }
        return await server.handle(message)
    }

    /// Whether this message needs the app's live state — first by method, then
    /// by the specific tool/resource it targets.
    ///
    /// A message that doesn't parse — or carries no method — is deliberately NOT
    /// worth launching an app for: it is dispatched as-is so the server answers
    /// with its own parse/invalid-request error. Likewise a `tools/call` with no
    /// `name`: the server will reject it, and there is nothing to look a flag up
    /// by, so it must not open anything.
    private func needsLiveApp(appID: String, message: String) -> Bool {
        guard let data = message.data(using: .utf8),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let method = root["method"] as? String,
            Self.methodsRequiringLiveApp.contains(method)
        else { return false }
        let params = root["params"] as? [String: Any] ?? [:]
        // `tools/call` names its target in `params.name`, `resources/read` in
        // `params.uri` — the two shapes `MCPAppServer.handle` reads.
        let target = (method == "tools/call" ? params["name"] : params["uri"]) as? String
        guard let target else { return false }
        return requiresLiveApp(appID, method, target)
    }

    /// Bounded wait — never an unbounded spin. Uses a deadline rather than a
    /// fixed iteration count so the poll interval can change without silently
    /// changing the timeout.
    private func waitUntilOpen(_ appID: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: launchTimeout)
        while ContinuousClock.now < deadline {
            // Checked explicitly because the sleep below swallows cancellation:
            // on a cancelled task `Task.sleep` returns IMMEDIATELY, so without
            // this the loop would busy-spin the main actor for the whole
            // `launchTimeout` — a UI freeze, not just a missed cancellation.
            try Task.checkCancellation()
            if isAppOpen(appID) { return }
            try? await Task.sleep(for: pollInterval)
        }
        guard isAppOpen(appID) else { throw AppDispatchFailure.launchTimedOut(appID) }
    }
}
