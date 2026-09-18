import Testing
import Foundation
import SwiftUI
import AinkradAppKit
@testable import AinkradHostRuntime
@testable import Ainkrad

/// Generation 11's host half: resolving which mode a pane opens in, and keeping
/// that resolution honest as the setting and the pane state change.
@Suite("Basic Mode — host")
@MainActor
struct PluginModeHostTests {

    // MARK: - Resolution

    @Test("With no override, an app opens in its declared mode")
    func declaredModeWins() {
        let store = makeStore()
        #expect(store.effectiveMode(for: app(mode: .basic)) == .basic)
        #expect(store.effectiveMode(for: app(mode: .advanced)) == .advanced)
    }

    @Test("A user override beats the declared mode")
    func overrideBeatsDeclared() {
        let store = makeStore()
        store.setModeOverride("fixture", .advanced)
        #expect(store.effectiveMode(for: app(mode: .basic)) == .advanced)
    }

    @Test("Clearing the override falls back to the declared mode, not to advanced")
    func resetRestoresDeclared() {
        let store = makeStore()
        store.setModeOverride("fixture", .advanced)
        store.setModeOverride("fixture", nil)
        #expect(store.effectiveMode(for: app(mode: .basic)) == .basic)
    }

    @Test("An app with no basic mode always resolves advanced, whatever is stored")
    func nonConformingAppIgnoresTheSetting() {
        // A stale override — from before an app dropped its basic mode, or
        // written against a different build — must not put an app into a mode
        // it has no root view for.
        let store = makeStore()
        store.setModeOverride("fixture", .basic)
        #expect(store.effectiveMode(for: app(mode: .basic, supportsModes: false)) == .advanced)
    }

    @Test("Overrides are per app and do not leak across ids")
    func overridesAreScopedByAppID() {
        let store = makeStore()
        store.setModeOverride("fixture", .basic)
        var other = app(mode: .advanced)
        other = RegisteredApp(id: "other", displayName: other.displayName, icon: other.icon,
                              isEnabledByDefault: true, source: other.source,
                              makeRootView: other.makeRootView,
                              makeSettingsView: other.makeSettingsView,
                              chromeFill: other.chromeFill)
        other.makeRootViewForMode = { _ in AnyView(EmptyView()) }
        #expect(store.effectiveMode(for: other) == .advanced)
    }

    // MARK: - The mode-aware root view

    @Test("A non-conforming app falls back to its mode-less root view")
    func fallbackKeepsPreGeneration11AppsWorking() {
        var built: [String] = []
        var registered = app(mode: .advanced, supportsModes: false)
        registered = RegisteredApp(id: registered.id, displayName: registered.displayName,
                                   icon: registered.icon, isEnabledByDefault: true,
                                   source: registered.source,
                                   makeRootView: { built.append("modeless"); return AnyView(EmptyView()) },
                                   makeSettingsView: { AnyView(EmptyView()) },
                                   chromeFill: { nil })
        _ = registered.makeRootView(mode: .basic)
        #expect(built == ["modeless"],
                "an app that never opted in must keep using its only factory")
    }

    @Test("A conforming app is built FOR the mode, not filtered after the fact")
    func modeReachesTheApp() {
        var asked: [PluginMode] = []
        var registered = app(mode: .basic)
        registered.makeRootViewForMode = { mode in
            asked.append(mode)
            return AnyView(EmptyView())
        }
        _ = registered.makeRootView(mode: .basic)
        _ = registered.makeRootView(mode: .advanced)
        #expect(asked == [.basic, .advanced])
    }

    // MARK: - Per-pane state

    @Test("A fresh pane carries no mode of its own, so it follows the setting")
    func freshPaneFollowsTheSetting() {
        // `nil` is the load-bearing state: it means "keep following the app's
        // default", so changing the setting moves every pane never switched.
        #expect(Block(appID: "fixture").mode == nil)
    }

    @Test("Switching one pane does not move another pane of the same app")
    func switchingIsPerPane() {
        let a = Block(appID: "fixture")
        let b = Block(appID: "fixture")
        a.mode = .advanced
        #expect(a.mode == .advanced)
        #expect(b.mode == nil, "the sibling must still follow the setting")
    }

    @Test("Switching a pane does not rewrite the app's default")
    func switchingDoesNotPersist() {
        // The product decision this guards: if reaching for advanced once wrote
        // the setting, the next open would silently be advanced too and the
        // setting would erode to whichever mode was last used.
        let store = makeStore()
        let block = Block(appID: "fixture")
        block.mode = .advanced
        #expect(store.modeOverride("fixture") == nil)
        #expect(store.effectiveMode(for: app(mode: .basic)) == .basic)
    }

    // MARK: - Persistence

    @Test("A v2 appearance document still loads, keeping the user's settings")
    func schemaBumpKeepsExistingSettings() {
        // Bumping currentSchemaVersion without an identity migrator does not
        // quietly keep working: FileDocumentStore walks the chain one step at a
        // time and fails the whole load on a missing step, dropping every
        // user's per-app opacity, blur, presentation override and fonts.
        #expect(AppAppearanceDocument.currentSchemaVersion == 3)
        #expect(AppAppearanceDocument.migrators.contains { $0.fromVersion == 2 },
                "v2 -> v3 needs a migrator even though the payload is unchanged")
    }

    @Test("A mode override survives a round trip")
    func overrideRoundTrips() {
        let persistence = InMemoryPersistenceStore()
        let first = AppAppearanceStore(persistence: persistence)
        first.setModeOverride("fixture", .basic)
        let second = AppAppearanceStore(persistence: persistence)
        #expect(second.modeOverride("fixture") == .basic)
    }

    @Test("Mode and presentation overrides are independent")
    func modeAndPresentationDoNotCollide() {
        let store = makeStore()
        store.setModeOverride("fixture", .basic)
        store.setPresentationOverride("fixture", .overlay)
        store.setModeOverride("fixture", nil)
        #expect(store.presentationOverride("fixture") == .overlay,
                "clearing one override must not clear the other")
    }

    // MARK: - The built-in apps

    @Test("Hoard offers a basic mode, and Scry deliberately does not")
    func builtInsOptInIndividually() {
        // Both take `RegisteredApp.builtIn`'s cast, not `PluginLoader`'s — which
        // is exactly why that cast had to be added in two places. Scry is the
        // proof that opting out costs nothing: a HUD canvas the assistant
        // drives has no meaningful basic mode, and it says so by not conforming.
        #expect((HoardApp.self as Any) as? AinkradAppModes.Type != nil)
        #expect((ScryApp.self as Any) as? AinkradAppModes.Type == nil,
                "Scry is deliberately excluded from Basic Mode")
    }

    @Test("A built-in's declared mode reaches its registration")
    func builtInDeclaredModeIsCarried() {
        // `RegisteredApp.builtIn` used to hardcode `presentation: .pane` and had
        // no mode at all, so a built-in could not declare either.
        let registered = RegisteredApp.builtIn(
            HoardApp.self, host: stubHostServices(), mode: .basic)
        #expect(registered.mode == .basic)
        #expect(registered.supportsModes)
    }

    // MARK: - Fixtures

    private func stubHostServices() -> HostServices {
        HostServicesImpl(
            appID: "hoard",
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: AgentContextRegistryHub(),
            actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(), signalHub: SignalEmitterHub(),
            declaredPresentation: .pane, declaredMode: .basic,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore())
        )
    }

    private func makeStore() -> AppAppearanceStore {
        AppAppearanceStore(persistence: InMemoryPersistenceStore())
    }

    private func app(mode: PluginMode, supportsModes: Bool = true) -> RegisteredApp {
        var registered = RegisteredApp(
            id: "fixture",
            displayName: "Fixture",
            icon: "circle",
            isEnabledByDefault: true,
            source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        registered.mode = mode
        if supportsModes {
            registered.makeRootViewForMode = { _ in AnyView(EmptyView()) }
        }
        return registered
    }
}
