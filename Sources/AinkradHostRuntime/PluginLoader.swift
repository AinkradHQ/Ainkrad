import SwiftUI
import Foundation
import AinkradAppKit
// Scoped import: the host's own `@main` struct is named `AinkradHostApp`
// (`App/AinkradApp.swift`), so this scoped import binds the bare name
// `AinkradApp` to the SDK protocol.
import protocol AinkradAppKit.AinkradApp

/// Discovers `.bundle`s in the given directories and turns the loadable ones
/// into `RegisteredApp`s. Every failure is isolated: it is logged, recorded,
/// and skipped — the host always finishes loading whatever it can.
@MainActor
public final class PluginLoader {
    private let signaturePolicy: PluginSignaturePolicy
    private let minSupportedAPIVersion: Int
    private let makeHostServices: (String, PluginPresentation) -> HostServices

    public init(signaturePolicy: PluginSignaturePolicy,
         minSupportedAPIVersion: Int = GenerationSupport.minSupported,
         makeHostServices: @escaping (String, PluginPresentation) -> HostServices) {
        self.signaturePolicy = signaturePolicy
        self.minSupportedAPIVersion = minSupportedAPIVersion
        self.makeHostServices = makeHostServices
    }

    /// Discovers every bundle in `directories`, resolves same-`appID` collisions
    /// BEFORE anything is loaded, then loads only the winners.
    ///
    /// Dedup by appID keeps the LAST directory's bundle — so a sideloaded
    /// `DevPlugins` build overrides an installed release of the same app in
    /// `Plugins` (directories are passed [Plugins, DevPlugins], dev last). In
    /// production there is no `DevPlugins`, so this is a no-op.
    ///
    /// WHY the dedup must precede loading, not follow it. `loadBundle` calls
    /// `Bundle.load()`, i.e. `dlopen`. Two bundles built from the same sources
    /// define the same Objective-C-registered class names, and the runtime
    /// registers a class name ONCE: the second image's copy is a duplicate and
    /// every by-name lookup — including `Bundle.principalClass` — keeps
    /// resolving to the image that was loaded FIRST. (Verified directly: two
    /// bundles with a shared principal class, both `load()`ing successfully,
    /// and the second bundle's `principalClass` handing back the first bundle's
    /// class, with objc logging "Class … is implemented in both".)
    ///
    /// So a post-load dedup was cosmetic: the `RegisteredApp` it kept was the
    /// dev one, but the `appType` inside it — and therefore every capability
    /// cast, `AinkradAppMCP` and `AinkradAppTeardown` included — came from the
    /// catalog image. A new capability compiled into the dev build was simply
    /// absent, with nothing reported anywhere. Deciding the winner from the
    /// Info.plist (`appID` is parsed before any code runs) and `dlopen`ing only
    /// that bundle removes the ambiguity at the source, and stops two copies of
    /// a plugin's code entering the process at all.
    ///
    /// A shadowed bundle is NOT a failure — being overridden is the intended
    /// outcome, and `failures` drives a user-facing "couldn't be loaded"
    /// banner. It is logged instead, naming both paths. If the winner then
    /// fails validation or fails to load we fail CLOSED and report that: never
    /// fall back to the shadowed bundle, because silently running an older
    /// build is the entire class of bug this ordering exists to prevent.
    public func loadAll(from directories: [URL]) -> (apps: [RegisteredApp], failures: [PluginLoadFailure]) {
        var apps: [RegisteredApp] = []
        var failures: [PluginLoadFailure] = []
        var winnerByID: [String: URL] = [:]
        var order: [String] = []

        // Phase 1 — discovery. Info.plist only; no `dlopen` happens here.
        for dir in directories {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in entries where url.pathExtension == "bundle" {
                switch inspect(at: url) {
                case .success(let inspected):
                    let appID = inspected.metadata.appID
                    if let shadowed = winnerByID[appID] {
                        // Not a failure: an intentionally-overridden release.
                        // This line is the one that makes an override visible
                        // instead of costing an afternoon of debugging.
                        Log.registry.notice("""
                            Plugin \(appID, privacy: .public) found in more than one directory: \
                            \(url.path, privacy: .public) overrides \(shadowed.path, privacy: .public). \
                            Loading \(url.path, privacy: .public); the shadowed bundle is not loaded.
                            """)
                    } else {
                        order.append(appID)
                    }
                    winnerByID[appID] = url
                case .failure(let rejection):
                    // Metadata that will not parse has no appID, so such a
                    // bundle can never be known to be shadowed — it is always
                    // reported. Validation and signature checks run in phase 2,
                    // on winners only, so a shadowed bundle's problems stay
                    // silent: it was never going to be loaded.
                    failures.append(PluginLoadFailure(url: url, reason: rejection.reason))
                    Log.registry.error("Skipped plugin \(url.lastPathComponent, privacy: .public): \(rejection.reason, privacy: .public)")
                }
            }
        }

        // Phase 2 — load the winners, in first-seen appID order.
        for appID in order {
            guard let url = winnerByID[appID] else { continue }
            switch loadBundle(at: url) {
            case .success(let app):
                apps.append(app)
            case .failure(let rejection):
                failures.append(PluginLoadFailure(url: url, reason: rejection.reason))
                Log.registry.error("Skipped plugin \(url.lastPathComponent, privacy: .public): \(rejection.reason, privacy: .public)")
            }
        }
        return (apps, failures)
    }

    /// A bundle's identity as read from disk, with no code loaded. Split out of
    /// `loadBundle` so `loadAll` can pick a winner per `appID` before `dlopen`.
    private struct InspectedBundle {
        let bundle: Bundle
        let info: [String: Any]
        let metadata: PluginBundleMetadata
    }

    /// Phase-1 read: open the bundle and parse its Info.plist metadata. Parsing
    /// only — validation and the signature check stay in `loadBundle`, so a
    /// shadowed bundle is never judged on criteria it will never be held to.
    private func inspect(at url: URL) -> Result<InspectedBundle, PluginRejection> {
        guard let bundle = Bundle(url: url) else { return .failure(PluginRejection(reason: "not a bundle")) }
        guard let info = bundle.infoDictionary else { return .failure(PluginRejection(reason: "missing Info.plist")) }
        switch PluginBundleMetadata.parse(infoDictionary: info) {
        case .success(let m): return .success(InspectedBundle(bundle: bundle, info: info, metadata: m))
        case .failure(let e): return .failure(PluginRejection(reason: "metadata: \(e)"))
        }
    }

    /// Loads and validates a single bundle into a `RegisteredApp`. Public so the
    /// installer can register a freshly-installed bundle without a relaunch.
    /// This is the ONLY place `Bundle.load()` is reached from — `loadAll` calls
    /// it exactly once per winning `appID`.
    public func loadBundle(at url: URL) -> Result<RegisteredApp, PluginRejection> {
        let inspected: InspectedBundle
        switch inspect(at: url) {
        case .success(let i): inspected = i
        case .failure(let rejection): return .failure(rejection)
        }
        let bundle = inspected.bundle
        let info = inspected.info
        let metadata = inspected.metadata

        if case .failure(let rejection) = PluginValidator.validate(metadata, infoDictionary: info, minSupportedAPIVersion: minSupportedAPIVersion) {
            return .failure(rejection)
        }

        if case .failure(let rejection) = signaturePolicy.validate(bundleURL: url) {
            return .failure(PluginRejection(reason: "signature: \(rejection.reason)"))
        }

        // WHY not `bundle.load()`: see `PluginLoadDiagnostics`. The bare `Bool`
        // discards dyld's message, which is the only thing that names the
        // missing symbol.
        do {
            try bundle.loadAndReturnError()
        } catch {
            let nsError = error as NSError
            let diagnosis = PluginLoadDiagnostics.diagnose(nsError)
            // The banner gets one sentence; the log keeps everything, so a
            // truncated banner never costs us the underlying detail.
            Log.registry.error("Bundle load failed for \(url.lastPathComponent, privacy: .public): \(diagnosis.log, privacy: .public)")
            return .failure(PluginRejection(reason: diagnosis.banner))
        }
        guard let principal = bundle.principalClass as? AinkradPluginEntryPoint.Type else {
            return .failure(PluginRejection(reason: "principal class missing or not AinkradPluginEntryPoint"))
        }

        // This is the one line that runs third-party plugin code in-process:
        // a `fatalError` (or other crash) inside plugin code here will crash
        // loading. Inherent to in-process loading — isolating it would need a
        // subprocess/XPC boundary, out of scope here.
        let appType = principal.app()
        let host = makeHostServices(metadata.appID, metadata.presentation)
        // Generation 8: teardown is discovered by CAST, never required. A
        // generation-7 bundle fails this cast and is simply left alone — which
        // is the whole point of adding capability this way rather than as a new
        // protocol requirement (an added requirement has no witness in an
        // already-compiled bundle, and the bundle stops loading entirely).
        var teardown: (@MainActor () -> Void)?
        if let teardownable = appType as? AinkradAppTeardown.Type,
           let identified = host as? PluginInstanceIdentity {
            let instance = identified.instanceID
            teardown = { teardownable.teardown(instance: instance) }
        }
        // Same cast-based discovery, for MCP capability.
        var mcpServerFactory: (@MainActor () -> MCPAppServer)?
        if let mcpCapable = appType as? AinkradAppMCP.Type {
            mcpServerFactory = { mcpCapable.makeMCPServer(host: host) }
        }
        // Generation 10, same discipline again. The factory is captured here
        // but NOT called: construction waits until the user has approved the
        // app's declared subscriptions.
        var signalObserverFactory: (@MainActor () -> any PluginSignalObserver)?
        if let observing = appType as? AinkradAppSignalObserving.Type {
            signalObserverFactory = { observing.makeSignalObserver(host: host) }
        }
        // Read straight from the Info.plist, deliberately outside
        // `PluginBundleMetadata.parse`. That parse is ABI-frozen and strict, so
        // folding this key into it would make every generation-8 and -9 bundle
        // — none of which can carry the key — fail to parse and vanish from the
        // user's launcher. A notification feature must not uninstall apps.
        let declaredSubscriptions =
            (info[PluginInfoKey.signalSubscriptions] as? [String]) ?? []
        return .success(.plugin(appType, url: url, apiVersion: metadata.apiVersion, host: host,
                                presentation: metadata.presentation, teardown: teardown,
                                mcpServerFactory: mcpServerFactory,
                                signalObserverFactory: signalObserverFactory,
                                declaredSignalSubscriptions: declaredSubscriptions))
    }
}

extension RegisteredApp {
    /// Adapts a dynamically-loaded `AinkradApp` type, binding it to its scoped
    /// host services. Plugins are enabled by default; the registry override
    /// still applies.
    @MainActor
    public static func plugin(_ app: any AinkradApp.Type, url: URL, apiVersion: Int, host: HostServices,
                              presentation: PluginPresentation,
                              teardown: (@MainActor () -> Void)? = nil,
                              mcpServerFactory: (@MainActor () -> MCPAppServer)? = nil,
                              signalObserverFactory: (@MainActor () -> any PluginSignalObserver)? = nil,
                              declaredSignalSubscriptions: [String] = []) -> RegisteredApp {
        var registered = RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            isEnabledByDefault: true,
            source: .plugin(url: url, apiVersion: apiVersion),
            // Generation 8: ONE theme delivery path.
            //
            // `HostServices.theme` and the SDK's `@Entry` environment keys were
            // disjoint mechanisms carrying the same data — a plugin could read
            // either, they were injected from different places, and nothing
            // guaranteed they agreed. The environment wins (it is what every
            // `AinkradAppKit` component already reads, and it is per-view, so a
            // preview or a nested surface can override it). `HostServices.theme`
            // is now the *injection point*: the host feeds the environment from
            // it here, so a plugin's own scoped theme is authoritative for its
            // subtree rather than whatever the host root happened to publish.
            //
            // Read inside the closure so `HostTheme`'s `@Observable` tokens stay
            // live — a theme change re-renders the plugin, as before.
            makeRootView: { AnyView(app.makeRootView(host: host).ainkradHostTheme(host.theme)) },
            makeSettingsView: { AnyView(app.makeSettingsView(host: host).ainkradHostTheme(host.theme)) },
            chromeFill: { app.chromeFill(host: host) },
            presentation: presentation
        )
        registered.teardown = teardown
        registered.mcpServerFactory = mcpServerFactory
        registered.signalObserverFactory = signalObserverFactory
        registered.declaredSignalSubscriptions = declaredSignalSubscriptions
        registered.settingsCatalog = { app.settingsCatalog(host: host) }
        return registered
    }
}
