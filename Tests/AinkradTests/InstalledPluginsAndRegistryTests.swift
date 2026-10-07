import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad

@MainActor
struct InstalledPluginsAndRegistryTests {
    private func plugin(_ id: String) -> RegisteredApp {
        RegisteredApp(
            id: id, displayName: id, icon: "app", isEnabledByDefault: true,
            source: .plugin(url: URL(fileURLWithPath: "/\(id).bundle"), apiVersion: 1),
            makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }
    private func builtIn(_ id: String) -> RegisteredApp {
        RegisteredApp(
            id: id, displayName: id, icon: "app", isEnabledByDefault: true, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }

    @Test("installed-plugins document round-trips")
    func docRoundTrip() {
        let store = InMemoryPersistenceStore()
        var doc = InstalledPluginsDocument()
        doc.installed["hello"] = .init(version: "1.0.0", sourceRepo: "o/hello")
        store.save(doc)
        #expect(store.load(InstalledPluginsDocument.self) == doc)
    }

    @Test("register appends a plugin and replaces by id")
    func registerAppendsReplaces() {
        let r = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        r.install(builtIn: [builtIn("terminal")])
        r.register(plugin("hello"))
        #expect(r.allApps.map(\.id) == ["terminal", "hello"])
        r.register(plugin("hello"))  // same id → replace, not duplicate
        #expect(r.allApps.map(\.id) == ["terminal", "hello"])
    }

    @Test("register refuses to shadow a built-in id")
    func registerRefusesBuiltIn() {
        let r = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        r.install(builtIn: [builtIn("terminal")])
        r.register(plugin("terminal"))  // must be ignored
        #expect(r.allApps.count == 1)
        #expect(r.allApps.first?.source == .builtIn)
    }

    @Test("deregister removes only a plugin")
    func deregister() {
        let r = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        r.install(builtIn: [builtIn("terminal")])
        r.register(plugin("hello"))
        r.deregister(id: "hello")
        #expect(r.allApps.map(\.id) == ["terminal"])
        r.deregister(id: "terminal")  // built-in: ignored
        #expect(r.allApps.map(\.id) == ["terminal"])
    }
}
