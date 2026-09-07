import Testing
import Foundation
import SwiftUI
@testable import Ainkrad
import AinkradHostRuntime
import AinkradAppKit

/// Generation 8: the host mints per-instance identity and calls teardown.
@MainActor
@Suite("Plugin lifecycle")
struct PluginLifecycleTeardownTests {

    private func registry() -> BuiltInAppRegistry {
        BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
    }

    private func app(_ id: String, teardown: (@MainActor () -> Void)? = nil) -> RegisteredApp {
        var registered = RegisteredApp(
            id: id, displayName: id, icon: "app", isEnabledByDefault: true,
            source: .plugin(url: URL(fileURLWithPath: "/tmp/\(id).bundle"), apiVersion: 8),
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        registered.teardown = teardown
        return registered
    }

    @Test("Deregistering a plugin calls its teardown")
    func deregisterCallsTeardown() {
        final class Flag { var torndown = false }
        let flag = Flag()
        let reg = registry()
        reg.install(builtIn: [], loaded: [app("lore", teardown: { flag.torndown = true })])

        reg.deregister(id: "lore")

        // Without this, a removed plugin kept its watchers, timers, open
        // databases and file descriptors for the rest of the process.
        #expect(flag.torndown)
    }

    /// The host-side half of teardown: caches keyed on the app id (the
    /// activator's memoized MCP server) must be dropped on the SAME seam, or
    /// they outlive the instance they were built over.
    @Test("Deregistering also runs the host-side teardown hook, after the plugin's own")
    func deregisterEvictsHostSideCaches() {
        final class Log { var events: [String] = [] }
        let log = Log()
        let reg = registry()
        reg.onAppTornDown = { log.events.append("host:\($0)") }
        reg.install(builtIn: [], loaded: [app("lore", teardown: { log.events.append("plugin") })])

        reg.deregister(id: "lore")

        #expect(log.events == ["plugin", "host:lore"])
    }

    @Test("A built-in ignored by deregister does not fire the host hook")
    func builtInDoesNotFireHostHook() {
        final class Log { var ids: [String] = [] }
        let log = Log()
        var builtIn = RegisteredApp(
            id: "sage", displayName: "Sage", icon: "app", isEnabledByDefault: true,
            source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        builtIn.teardown = nil
        let reg = registry()
        reg.onAppTornDown = { log.ids.append($0) }
        reg.install(builtIn: [builtIn])

        reg.deregister(id: "sage")

        #expect(log.ids.isEmpty, "a still-installed app's server must stay cached")
    }

    @Test("A plugin without teardown deregisters cleanly")
    func generationSevenPluginStillDeregisters() {
        let reg = registry()
        reg.install(builtIn: [], loaded: [app("legacy")])
        reg.deregister(id: "legacy")   // teardown is nil — must not crash
        #expect(reg.allApps.isEmpty)
    }

    @Test("Built-ins are never torn down by deregister")
    func builtInsAreUntouched() {
        final class Flag { var torndown = false }
        let flag = Flag()
        var builtIn = RegisteredApp(
            id: "sage", displayName: "Sage", icon: "app", isEnabledByDefault: true,
            source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        builtIn.teardown = { flag.torndown = true }
        let reg = registry()
        reg.install(builtIn: [builtIn])

        reg.deregister(id: "sage")

        #expect(!flag.torndown)
        #expect(reg.allApps.count == 1, "a built-in must not be removable")
    }

    @Test("Each HostServicesImpl mints its own instance id")
    func hostMintsDistinctIdentity() {
        let first = makeHost(), second = makeHost()
        // The replacement for `ObjectIdentifier(host as AnyObject)`, which was
        // an address and could be recycled onto a different host.
        #expect(first.instanceID != second.instanceID)
        #expect(first.instanceID == first.instanceID, "must be stable for one instance")
        // Discovered by cast, per the freeze rule — never a HostServices requirement.
        #expect((first as any HostServices) as? PluginInstanceIdentity != nil)
    }

    private func makeHost() -> HostServicesImpl {
        HostServicesImpl(
            appID: "test",
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: AgentContextRegistryHub(),
            actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(), signalHub: SignalEmitterHub(),
            declaredPresentation: .pane,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore()))
    }
}

/// Generation 8: `apps.open` reports what happened instead of silently
/// doing nothing.
@MainActor
@Suite("Plugin launch outcome")
struct PluginLaunchOutcomeTests {

    @Test("Opening an unknown app reports it rather than succeeding silently")
    func unknownAppIsReported() {
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .unknown }
        let launcher = HostAppLauncher(appID: "leyline", hub: hub)

        #expect(launcher.openReportingOutcome(appID: "gitmage", payload: "{}")
                == .unknownApp("gitmage"))
        // And no payload is left queued for an app that never opens.
        #expect(hub.takePending(for: "gitmage") == nil)
    }

    @Test("A disabled app is distinguished from a missing one")
    func disabledIsDistinct() {
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .disabled }
        let launcher = HostAppLauncher(appID: "leyline", hub: hub)
        #expect(launcher.openReportingOutcome(appID: "gitmage", payload: nil)
                == .disabled("gitmage"))
    }

    @Test("An available app opens and receives its payload")
    func availableAppOpens() {
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .available }
        var opened: String?
        hub.setOpenHandler { opened = $0 }
        let launcher = HostAppLauncher(appID: "leyline", hub: hub)

        #expect(launcher.openReportingOutcome(appID: "gitmage", payload: "payload") == .opened)
        #expect(opened == "gitmage")
        #expect(hub.takePending(for: "gitmage") == "payload")
    }

    @Test("With no availability provider, behaviour is unchanged")
    func defaultsToAvailable() {
        // Generation-7 parity: tests and early bootstrap have no provider.
        let hub = PluginLaunchHub()
        let launcher = HostAppLauncher(appID: "a", hub: hub)
        #expect(launcher.openReportingOutcome(appID: "b", payload: nil) == .opened)
    }
}
