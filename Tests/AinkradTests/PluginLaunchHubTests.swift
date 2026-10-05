import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("PluginLaunchHub")
@MainActor
struct PluginLaunchHubTests {
    @Test("payload is delivered to the target app exactly once")
    func deliverOnce() {
        let hub = PluginLaunchHub()
        hub.enqueue(target: "gitmage", payload: "{\"kind\":\"ssh\"}")
        #expect(hub.takePending(for: "gitmage") == "{\"kind\":\"ssh\"}")
        #expect(hub.takePending(for: "gitmage") == nil)  // consumed
    }

    @Test("payloads are isolated per target app")
    func perApp() {
        let hub = PluginLaunchHub()
        hub.enqueue(target: "gitmage", payload: "A")
        #expect(hub.takePending(for: "leyline") == nil)
        #expect(hub.takePending(for: "gitmage") == "A")
    }

    @Test("a transient payload is delivered while fresh, once")
    func transientFresh() {
        let hub = PluginLaunchHub()
        let t0 = Date(timeIntervalSince1970: 1000)
        hub.enqueueTransient(target: "whisper", payload: "acct", lifetime: 5, now: t0)
        #expect(hub.takePending(for: "whisper", now: t0.addingTimeInterval(1)) == "acct")
        #expect(hub.takePending(for: "whisper", now: t0.addingTimeInterval(2)) == nil)
    }

    @Test("an expired transient payload is never delivered")
    func transientExpires() {
        let hub = PluginLaunchHub()
        let t0 = Date(timeIntervalSince1970: 1000)
        hub.enqueueTransient(target: "rune", payload: "stale", lifetime: 5, now: t0)
        #expect(hub.takePending(for: "rune", now: t0.addingTimeInterval(6)) == nil)
    }

    @Test("a transient payload never replaces a real pending launch")
    func transientDoesNotClobber() {
        let hub = PluginLaunchHub()
        hub.enqueue(target: "rune", payload: "ssh-session")
        hub.enqueueTransient(target: "rune", payload: "from-signal")
        #expect(hub.takePending(for: "rune") == "ssh-session")
    }

    @Test("requestOpen fires the wired handler with the app id")
    func requestOpenFires() {
        let hub = PluginLaunchHub()
        var opened: [String] = []
        hub.setOpenHandler { opened.append($0) }
        hub.requestOpen("gitmage")
        #expect(opened == ["gitmage"])
    }

    @Test("open via the facade enqueues then requests open")
    func facade() {
        let hub = PluginLaunchHub()
        var opened: [String] = []
        hub.setOpenHandler { opened.append($0) }
        let launcher = HostAppLauncher(appID: "leyline", hub: hub)
        launcher.open(appID: "gitmage", payload: "P")
        #expect(opened == ["gitmage"])
        let gitmageSide = HostAppLauncher(appID: "gitmage", hub: hub)
        #expect(gitmageSide.takePendingLaunch() == "P")
    }

    /// The v0.16.0 rename broke every INSTALLED plugin that launches another app
    /// by its old id. Leyline v0.6.1 ships `open(appID: "terminal")`; without an
    /// alias that returns `.unknownApp` and its connect button silently does
    /// nothing. The host resolves retired ids so already-installed plugins keep
    /// working without an update of their own.
    @Test("a retired app id still launches its replacement")
    func retiredIDLaunchesReplacement() {
        let hub = PluginLaunchHub()
        var opened: [String] = []
        hub.setOpenHandler { opened.append($0) }
        hub.setAvailabilityProvider { $0 == "rune" ? .available : .unknown }

        let leyline = HostAppLauncher(appID: "leyline", hub: hub)
        let outcome = leyline.openReportingOutcome(appID: "terminal", payload: "SSH")

        #expect(outcome == .opened)
        #expect(opened == ["rune"])
        #expect(HostAppLauncher(appID: "rune", hub: hub).takePendingLaunch() == "SSH")
    }

    @Test("an unknown app that is not a retired id still reports unknown")
    func unknownStaysUnknown() {
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .unknown }
        let launcher = HostAppLauncher(appID: "leyline", hub: hub)
        #expect(launcher.openReportingOutcome(appID: "nope", payload: nil) == .unknownApp("nope"))
    }
}
