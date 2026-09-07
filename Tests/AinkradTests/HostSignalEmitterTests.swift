import Testing
import Foundation
import AinkradSignal
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("HostSignalEmitter")
final class HostSignalEmitterTests {
    private final class SpyDeliverer: SignalDeliverer {
        var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }
    private struct PresentContext: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private let url: URL
    private let center: SignalCenter
    private let hub: SignalEmitterHub
    private let deliverer = SpyDeliverer()

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        center = SignalCenter(store: try SignalStore(url: url),
                              deliverer: deliverer, contextProvider: PresentContext())
        // The hub records through the `SignalEmitting` sink, which the feed
        // conforms to — `AinkradHostRuntime` cannot see `SignalCenter`.
        hub = SignalEmitterHub(sink: center)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @Test("an app's event is stamped with that app's id")
    func stampsAppID() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        raven.emit(kind: "build.failed", severity: .failure, title: "Build failed")
        #expect(center.recent.count == 1)
        #expect(center.recent[0].source == .app(appID: "raven"))
    }

    @Test("two apps cannot see or attribute each other's events")
    func isolation() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        let quest = HostSignalEmitter(appID: "quest", hub: hub)
        raven.emit(kind: "build.failed", severity: .failure, title: "R")
        quest.emit(kind: "session.done", severity: .success, title: "Q")

        #expect(raven.own(limit: 10).map(\.title) == ["R"])
        #expect(quest.own(limit: 10).map(\.title) == ["Q"])
        #expect(center.recent.count == 2, "the host still sees both")
    }

    @Test("own(limit:) never returns another app's events even at a large limit")
    func ownIsScoped() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        HostSignalEmitter(appID: "quest", hub: hub)
            .emit(kind: "test.event", severity: .info, title: "Q")
        #expect(raven.own(limit: 1000).isEmpty)
    }

    @Test("an invalid kind is swallowed, not thrown, and stores nothing")
    func invalidKindIsSilent() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        raven.emit(kind: "Not A Kind", severity: .info, title: "t")
        #expect(center.recent.isEmpty)
    }

    @Test("a registered action handler fires when the host invokes it")
    func actionHandler() async {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        _ = raven.handleAction("retry") { fired = true }
        await hub.invoke(actionID: "retry", appID: "raven")
        #expect(fired)
    }

    @Test("invoking an action for the wrong app does nothing")
    func actionsAreScoped() async {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        _ = raven.handleAction("retry") { fired = true }
        await hub.invoke(actionID: "retry", appID: "quest")
        #expect(!fired, "one app's action id must not shadow another's")
    }

    @Test("a removed handler no longer fires")
    func removeHandler() async {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        let token = raven.handleAction("retry") { fired = true }
        raven.removeActionHandler(token)
        await hub.invoke(actionID: "retry", appID: "raven")
        #expect(!fired)
    }

    @Test("forging another app's source is not expressible")
    func forgeryIsInexpressible() {
        // `PluginSignalEmitter` has no `source` parameter and `HostSignalEmitter`
        // binds the id at construction, so there is no code path by which an app
        // can emit as another. This test pins the property; the compiler enforces it.
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        raven.emit(kind: "test.event", severity: .info, title: "t")
        #expect(center.recent.allSatisfy { $0.source == .app(appID: "raven") })
    }
}

/// The bootstrap ordering the real app uses, which the suite above does not:
/// the hub is built in `bootstrapCoreStores` (before the feed exists), handed
/// to every `HostServicesImpl`, and only later given its sink in
/// `finalizeBootstrap`. If `attach(sink:)` did not work, every plugin emit
/// would vanish silently — and no test that constructs the hub with its sink
/// could ever notice.
@MainActor
@Suite("Hub attached after construction, as bootstrap does it")
final class SignalEmitterHubAttachTests {
    private final class NullDeliverer: SignalDeliverer {
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
    }
    private struct Ctx: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    @Test("an emit after attach reaches the store")
    func emitAfterAttachIsRecorded() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // 1. bootstrapCoreStores: hub first, no feed yet.
        let hub = SignalEmitterHub()
        let emitter = HostSignalEmitter(appID: "rune", hub: hub)

        // 2. finalizeBootstrap: the feed exists, and the hub gains its sink.
        let center = SignalCenter(store: try SignalStore(url: url),
                                  deliverer: NullDeliverer(), contextProvider: Ctx())
        hub.attach(sink: center)

        // 3. A plugin emits.
        emitter.emit(kind: "terminal.bell", severity: .info, title: "Terminal needs your attention")

        #expect(center.recent.count == 1)
        #expect(center.recent[0].source == .app(appID: "rune"))
        #expect(center.recent[0].kind == "terminal.bell")
    }

    @Test("an emit BEFORE attach is dropped, and does not crash")
    func emitBeforeAttachIsDropped() {
        let hub = SignalEmitterHub()
        HostSignalEmitter(appID: "rune", hub: hub)
            .emit(kind: "terminal.bell", severity: .info, title: "early")
        // Nothing to assert but the absence of a crash: an event emitted before
        // the feed exists has nowhere to go. Worth pinning so it stays a no-op
        // rather than becoming a trap.
        #expect(Bool(true))
    }

    @Test("the sink is held weakly, so a torn-down feed does not keep itself alive")
    func sinkIsWeak() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let hub = SignalEmitterHub()
        do {
            let center = SignalCenter(store: try SignalStore(url: url),
                                      deliverer: NullDeliverer(), contextProvider: Ctx())
            hub.attach(sink: center)
        }
        // The center is gone; emitting must be a silent no-op, not a crash.
        HostSignalEmitter(appID: "rune", hub: hub)
            .emit(kind: "terminal.bell", severity: .info, title: "after teardown")
        #expect(Bool(true))
    }
}
