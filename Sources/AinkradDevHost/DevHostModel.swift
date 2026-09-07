import Foundation
import Observation
import AinkradAppKit
import AinkradHostRuntime

/// Drives the Dev Host's load-one-bundle contract: validate the bundle
/// through the SAME shared validation the real host and store review use,
/// then (only on a validation pass) load it in-process. Keeping validation
/// 100% real is what makes the Dev Host's rejection message match what a
/// developer would see from store review — see `AinkradHostRuntime.PluginValidator`.
@Observable
@MainActor
final class DevHostModel {
    enum State {
        case empty
        case invalid(String)
        case loaded(RegisteredApp)
    }

    private(set) var state: State = .empty

    /// Which of the plugin's two view factories the stage is showing.
    ///
    /// The Dev Host used to stage `makeRootView` and nothing else, so a
    /// plugin's settings — a surface the REAL host renders via
    /// `AppSettingsCatalog` — were unreachable here, and every settings
    /// claim went to review GUI-unverified because there was no way to look
    /// at them. Both factories are part of the `AinkradApp` contract; a host
    /// that exercises only one of them is not exercising the contract.
    enum Surface: String, CaseIterable {
        case root, settings
    }

    /// Reset to `.root` by `load`, never carried across bundles: the surface
    /// belongs to the app on the stage, and a reload that kept `.settings`
    /// would open a new plugin on a screen its author may not have.
    var surface: Surface = .root

    /// The in-process load step, injected so this model's validation path can
    /// be exercised end-to-end in tests without a compiled plugin binary
    /// (mirrors `PluginInstaller`'s `loadBundle` seam) while the default in
    /// the running app performs a REAL load via `PluginLoader`.
    private let loadBundle: (URL) -> Result<RegisteredApp, PluginRejection>

    init(loadBundle: @escaping (URL) -> Result<RegisteredApp, PluginRejection>) {
        self.loadBundle = loadBundle
    }

    /// Builds the model the running app uses: real validation AND a real
    /// in-process load via `PluginLoader`, backed by dev-scoped in-memory
    /// host services (mirrors `PluginLoaderTests.stubHost`).
    convenience init() {
        self.init(loadBundle: { url in
            PluginLoader(signaturePolicy: DevModeSignaturePolicy()) { appID, declaredPresentation in
                DevHostModel.makeHostServices(appID: appID, presentation: declaredPresentation)
            }.loadBundle(at: url)
        })
    }

    /// The three registry hubs, held for the process lifetime.
    ///
    /// `HostContextRegistry`, `HostActionRegistry` and `HostAppLauncher` all
    /// hold their hub `unowned` — the real host gets away with that because
    /// `AppEnvironment` owns them. `makeHostServices` used to construct each
    /// hub INLINE, so all three died the moment it returned and the first
    /// plugin to call `host.context.register(...)` aborted in
    /// `swift_unownedRetainStrong`. Any plugin that publishes agent context
    /// crashed the Dev Host on load, which is the one thing the Dev Host
    /// exists to rule out.
    static let contextHub = AgentContextRegistryHub()
    static let actionHub = AgentActionRegistryHub()
    static let launchHub = PluginLaunchHub()

    static func makeHostServices(appID: String, presentation: PluginPresentation) -> HostServices {
        HostServicesImpl(
            appID: appID,
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AinkradDevHost", isDirectory: true),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: contextHub,
            actionHub: actionHub,
            launchHub: launchHub,
            // The dev host has no feed; a plugin's emissions go nowhere, which
            // is the correct behaviour for a harness that only checks loading.
            signalHub: SignalEmitterHub(),
            declaredPresentation: presentation,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore())
        )
    }

    /// Validates `args.bundleURL` through the shared module, then loads it on
    /// a validation pass. `args.generation`, when set, overrides the
    /// otherwise-default `minSupportedAPIVersion == AinkradAppKit.apiVersion`
    /// floor — letting a developer pin the Dev Host to an older generation to
    /// exercise compatibility rejection locally.
    func load(_ args: LaunchArguments) {
        guard let bundle = Bundle(url: args.bundleURL), let info = bundle.infoDictionary else {
            state = .invalid("missing Info.plist")
            return
        }

        let metadata: PluginBundleMetadata
        switch PluginBundleMetadata.parse(infoDictionary: info) {
        case .success(let m):
            metadata = m
        case .failure(let error):
            state = .invalid("metadata: \(error)")
            return
        }

        // Defaults to the REAL host's floor, not to `current`. Defaulting to
        // `apiVersion` made the Dev Host stricter than the host it stands in
        // for: the deprecation window is `[minSupported ... current]`, so a
        // generation-8 bundle that the shipping host loads without complaint
        // was rejected here as unsupported, and the rejection message quoted a
        // range ("9-9") no host actually enforces. The whole value of this
        // screen is that its verdict matches what the developer will get.
        //
        // `args.generation` still overrides, which is what it is for: raising
        // the floor by hand to exercise a rejection locally.
        let minSupportedAPIVersion = args.generation ?? GenerationSupport.minSupported
        if case .failure(let rejection) = PluginValidator.validate(
            metadata, infoDictionary: info, minSupportedAPIVersion: minSupportedAPIVersion) {
            state = .invalid(rejection.reason)
            return
        }

        switch loadBundle(args.bundleURL) {
        case .success(let app):
            surface = .root
            state = .loaded(app)
        case .failure(let rejection):
            state = .invalid(rejection.reason)
        }
    }
}
