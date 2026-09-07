import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

@MainActor
@Suite("Signal badges")
final class SignalBadgeTests {
    private final class NullDeliverer: SignalDeliverer {
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
    }
    private struct Ctx: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private func makeCenter() throws -> (SignalCenter, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        return (SignalCenter(store: try SignalStore(url: url),
                            deliverer: NullDeliverer(), contextProvider: Ctx()), url)
    }

    @Test("per-app unread counts are independent, and reading one does not clear another")
    func perAppCounts() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = SignalBadgeModel(center: center)

        center.emit(SignalDraft(kind: "build.failed", severity: .failure, title: "a"),
                    from: .app(appID: "raven"))
        center.emit(SignalDraft(kind: "build.failed", severity: .failure, title: "b"),
                    from: .app(appID: "raven"))
        center.emit(SignalDraft(kind: "session.done", severity: .success, title: "c"),
                    from: .app(appID: "quest"))

        #expect(model.count(for: "raven") == 2)
        #expect(model.count(for: "quest") == 1)
        #expect(model.count(for: "lore") == 0)

        var ravenOnly = SignalFilter.all
        ravenOnly.sources = [.app(appID: "raven")]
        center.markAllRead(filter: ravenOnly)
        #expect(model.count(for: "raven") == 0)
        #expect(model.count(for: "quest") == 1,
                "reading one app's events must not clear another's")
    }

    @Test("host events do not land on any app's badge")
    func hostEventsAreNotAppBadges() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = SignalBadgeModel(center: center)
        center.emit(SignalDraft(kind: "run.finished", severity: .success, title: "h"), from: .host)
        #expect(model.count(for: "host") == 0, "'host' is not an app id")
        #expect(center.totalUnread == 1, "but the feed still counts it")
    }

    @Test("badge text caps so it cannot resize the surface it sits on")
    func badgeText() {
        #expect(SignalBadgeModel.badgeText(0) == nil)
        #expect(SignalBadgeModel.badgeText(9) == "9")
        #expect(SignalBadgeModel.badgeText(99) == "99")
        #expect(SignalBadgeModel.badgeText(100) == "99+")
    }
}

@MainActor
@Suite("Signal action routing")
struct SignalActionRouterTests {
    private func event(source: SignalSource) -> SignalEvent {
        SignalEvent(source: source, kind: "build.failed", severity: .failure, title: "t")
    }

    @Test("a safe action dispatches immediately")
    func safeActionDispatches() async {
        let hub = SignalEmitterHub()
        let emitter = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        _ = emitter.handleAction("rerun") { fired = true }

        let router = SignalActionRouter(hub: hub)
        let needsConfirmation = router.invoke(event(source: .app(appID: "raven")),
                                              SignalAction(id: "rerun", label: "Re-run"))
        #expect(needsConfirmation == nil, "a safe action needs no dialog")
        try? await Task.sleep(for: .milliseconds(60))
        #expect(fired)
    }

    @Test("a destructive action is returned for confirmation and NOT dispatched")
    func destructiveActionWaits() async {
        let hub = SignalEmitterHub()
        let emitter = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        _ = emitter.handleAction("wipe") { fired = true }

        let router = SignalActionRouter(hub: hub)
        let action = SignalAction(id: "wipe", label: "Delete", isDestructive: true)
        #expect(router.invoke(event(source: .app(appID: "raven")), action) == action)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(!fired, "a destructive action must not fire before the user confirms")

        router.dispatch(event(source: .app(appID: "raven")), action)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(fired, "and must fire once they do")
    }

    @Test("a host event's action is never routed to an app")
    func hostEventsDoNotRoute() async {
        let hub = SignalEmitterHub()
        var fired = false
        _ = HostSignalEmitter(appID: "raven", hub: hub).handleAction("rerun") { fired = true }
        SignalActionRouter(hub: hub).dispatch(event(source: .host),
                                              SignalAction(id: "rerun", label: "Re-run"))
        try? await Task.sleep(for: .milliseconds(60))
        #expect(!fired, "a host event must not invoke an app's handler that shares an id")
    }
}
