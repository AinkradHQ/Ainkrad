import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("BuiltInAppRegistry")
@MainActor
final class BuiltInAppRegistryTests {
    let store = InMemoryPersistenceStore()

    private func app(_ id: String, displayName: String, isEnabledByDefault: Bool) -> RegisteredApp {
        RegisteredApp(
            id: id, displayName: displayName, icon: "app",
            isEnabledByDefault: isEnabledByDefault, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil }
        )
    }

    private var stubApps: [RegisteredApp] {
        [
            app("terminal", displayName: "Terminal", isEnabledByDefault: true),
            app("settings", displayName: "Settings", isEnabledByDefault: false),
        ]
    }

    private func makeRegistry() -> BuiltInAppRegistry {
        let registry = BuiltInAppRegistry(persistence: store)
        registry.install(builtIn: stubApps)
        return registry
    }

    @Test("exposes all registered apps in order")
    func exposesAllRegisteredApps() {
        let registry = makeRegistry()
        #expect(registry.allApps.map { $0.id } == ["terminal", "settings"])
    }

    @Test("enabledApps reflects each app's default-enabled flag before any toggle")
    func defaultEnabledState() {
        let registry = makeRegistry()
        #expect(registry.isEnabled("terminal") == true)
        #expect(registry.isEnabled("settings") == false)
        #expect(registry.enabledApps.map { $0.id } == ["terminal"])
    }

    @Test("toggling enabled state updates in-memory state immediately")
    func togglingUpdatesInMemory() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "terminal")
        #expect(registry.isEnabled("terminal") == false)
        #expect(registry.enabledApps.isEmpty)
    }

    @Test("enabled state survives a simulated relaunch (fresh registry, same store)")
    func enabledStatePersists() {
        let firstLaunch = makeRegistry()
        firstLaunch.setEnabled(false, for: "terminal")
        firstLaunch.setEnabled(true, for: "settings")

        let secondLaunch = BuiltInAppRegistry(persistence: store)
        secondLaunch.install(builtIn: stubApps)

        #expect(secondLaunch.isEnabled("terminal") == false)
        #expect(secondLaunch.isEnabled("settings") == true)
    }
}
