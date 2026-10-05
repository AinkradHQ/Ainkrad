import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad

@MainActor
struct RegisteredAppRegistryTests {
    private func app(_ id: String, enabledByDefault: Bool = true) -> RegisteredApp {
        RegisteredApp(
            id: id, displayName: id.capitalized, icon: "app",
            isEnabledByDefault: enabledByDefault, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil }
        )
    }

    @Test("installed apps are exposed via allApps")
    func exposesInstalled() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [app("terminal")])
        #expect(registry.allApps.map(\.id) == ["terminal"])
    }

    @Test("default-enabled state comes from the app when no override exists")
    func defaultEnabled() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [app("a"), app("b", enabledByDefault: false)])
        #expect(registry.enabledApps.map(\.id) == ["a"])
    }

    @Test("an override flips and persists enabled state")
    func overridePersists() {
        let store = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: store)
        registry.install(builtIn: [app("a")])
        registry.setEnabled(false, for: "a")
        #expect(registry.enabledApps.isEmpty)

        let reloaded = BuiltInAppRegistry(persistence: store)
        reloaded.install(builtIn: [app("a")])
        #expect(reloaded.enabledApps.isEmpty)
    }

    @Test("a plugin with a built-in's id is dropped (built-in wins)")
    func builtInWinsConflict() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        let builtInTerminal = app("terminal")
        let pluginTerminal = RegisteredApp(
            id: "terminal", displayName: "Impostor", icon: "app",
            isEnabledByDefault: true, source: .plugin(url: URL(fileURLWithPath: "/x.bundle"), apiVersion: 1),
            makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
        registry.install(builtIn: [builtInTerminal], loaded: [pluginTerminal, app("notes")])
        #expect(registry.allApps.map(\.id) == ["terminal", "notes"])
        #expect(registry.allApps.first(where: { $0.id == "terminal" })?.displayName == "Terminal")
    }

    @Test("load failures are exposed for the App Store UI")
    func exposesFailures() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(
            builtIn: [app("terminal")], loaded: [],
            failures: [PluginLoadFailure(url: URL(fileURLWithPath: "/bad.bundle"), reason: "boom")])
        #expect(registry.loadFailures.map(\.reason) == ["boom"])
    }
}
