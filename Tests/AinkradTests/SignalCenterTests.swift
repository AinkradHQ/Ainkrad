import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("SignalCenter")
final class SignalCenterTests {
    private final class SpyDeliverer: SignalDeliverer {
        var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }

    private struct StubContext: SignalContextProviding {
        var deliveryContext: DeliveryContext
    }

    private let url: URL
    private let store: SignalStore
    private let deliverer = SpyDeliverer()
    private let center: SignalCenter

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        store = try SignalStore(url: url)
        center = SignalCenter(
            store: store,
            deliverer: deliverer,
            contextProvider: StubContext(deliveryContext: DeliveryContext(
                hostIsFrontmost: false, visibleAppIDs: [],
                systemDoNotDisturb: false, hostFocusMode: false)))
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @Test("event(id:) resolves a recorded event, and nil for an unknown id")
    func eventByID() throws {
        center.emit(draft(), from: .app(appID: "raven"))
        let emitted = try #require(center.recent.first)

        #expect(center.event(id: emitted.id)?.id == emitted.id)
        #expect(center.event(id: UUID()) == nil)
    }

    private func draft(_ kind: String = "install.completed",
                       _ severity: SignalSeverity = .success) -> SignalDraft {
        SignalDraft(kind: kind, severity: severity, title: "Something happened")
    }

    @Test("emitting stores the event, updates unread counts, and dispatches channels")
    func emitStoresAndDispatches() {
        center.emit(draft(), from: .host)
        #expect(center.recent.count == 1)
        #expect(center.totalUnread == 1)
        #expect(center.unreadCounts[.host] == 1)
        #expect(deliverer.delivered.count == 1)
        #expect(deliverer.delivered[0].1.contains(.feed))
        #expect(deliverer.delivered[0].1.contains(.banner), "user is away, success promotes to banner")
    }

    @Test("a rejected draft dispatches nothing and stores nothing")
    func rejectionIsSilent() {
        center.emit(SignalDraft(kind: "Bad Kind", severity: .info, title: "x"), from: .host)
        #expect(center.recent.isEmpty)
        #expect(deliverer.delivered.isEmpty)
    }

    @Test("a run event routes like any other, now that the exemption is gone")
    func runEventsAreOrdinary() {
        center.emit(draft("run.finished"), from: .host)
        #expect(center.recent.count == 1)
        #expect(deliverer.delivered[0].1.contains(.banner),
                "the exemption used to strip this; stripping it now means no banner at all")
    }

    @Test("marking read clears the unread count")
    func markRead() {
        center.emit(draft(), from: .host)
        center.markAllRead(filter: .all)
        #expect(center.totalUnread == 0)
    }

    @Test("a muted source is still recorded but never delivered beyond the feed")
    func mutedSource() {
        center.rules.mutedSources.insert(.host)
        center.emit(draft(), from: .host)
        #expect(center.recent.count == 1)
        #expect(deliverer.delivered[0].1 == [.feed])
    }

    @Test("with no store the center degrades to memory and keeps delivering")
    func degradedMode() {
        let degraded = SignalCenter(
            store: nil,
            deliverer: deliverer,
            contextProvider: StubContext(deliveryContext: DeliveryContext(
                hostIsFrontmost: true, visibleAppIDs: [],
                systemDoNotDisturb: false, hostFocusMode: false)))
        #expect(degraded.isDegraded)
        degraded.emit(draft(), from: .host)
        #expect(degraded.recent.count == 1, "in-memory ring buffer still serves the feed")
        #expect(!deliverer.delivered.isEmpty, "routing is unaffected by a dead store")
    }

    @Test("the in-memory ring buffer is bounded")
    func ringBufferBounded() {
        let degraded = SignalCenter(store: nil, deliverer: deliverer,
                                    contextProvider: StubContext(deliveryContext: DeliveryContext(
                                        hostIsFrontmost: true, visibleAppIDs: [],
                                        systemDoNotDisturb: false, hostFocusMode: false)))
        for i in 0..<250 {
            degraded.emit(SignalDraft(kind: "test.event", severity: .info, title: "e\(i)"), from: .host)
        }
        #expect(degraded.recent.count == SignalCenter.degradedBufferLimit)
        #expect(degraded.recent.first?.title == "e249", "newest first")
    }

    // MARK: - onEventRecorded

    /// Shared log so the ordering test can compare the SEQUENCE rather than
    /// only the contents.
    private final class OrderLog {
        var events: [String] = []
    }

    private final class LoggingDeliverer: SignalDeliverer {
        let log: OrderLog
        init(log: OrderLog) { self.log = log }
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            log.events.append("delivered")
        }
    }

    @Test("onEventRecorded fires AFTER delivery, never before")
    func recordedFiresAfterDelivery() throws {
        // The ordering cross-app subscriptions depend on: a subscribing app
        // must not be able to react to an event the user has not been shown
        // yet. Asserted rather than left as a comment, because moving one line
        // in `emit` would silently invert it.
        let log = OrderLog()
        // Held in a local, not passed inline: `SignalCenter.deliverer` is a
        // weak reference (a deliverer outliving the center it feeds is the
        // leak that seam exists to prevent), so an inline instance is gone
        // before the first emit and nothing is delivered at all.
        let logging = LoggingDeliverer(log: log)
        let observed = SignalCenter(
            store: try SignalStore(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("order-\(UUID().uuidString).sqlite")),
            deliverer: logging,
            contextProvider: StubContext(deliveryContext: DeliveryContext(
                hostIsFrontmost: false, visibleAppIDs: [],
                systemDoNotDisturb: false, hostFocusMode: false)))
        observed.onEventRecorded = { _ in log.events.append("recorded") }

        observed.emit(draft("order.check"), from: .host)
        #expect(log.events == ["delivered", "recorded"])
        _ = logging
    }

    @Test("onEventRecorded fires for a coalesced repeat too")
    func recordedFiresOnCoalesce() {
        // A repeat is still something that happened. A subscriber told only
        // about the first of five identical failures is misinformed, not
        // merely under-informed.
        var count = 0
        center.onEventRecorded = { _ in count += 1 }
        var repeated = draft("repeat.check")
        repeated.dedupeKey = "same"
        center.emit(repeated, from: .host)
        center.emit(repeated, from: .host)
        #expect(count == 2)
    }

    // MARK: - Activation goes somewhere

    private func event(source: SignalSource, deepLink: SignalDeepLink? = nil) -> SignalEvent {
        SignalEvent(source: source, kind: "test", severity: .info,
                    title: "t", deepLink: deepLink)
    }

    @Test("an event with no deep link still reveals the app that sent it")
    func activateFallsBackToTheSource() {
        var revealed: [String] = []
        var linked: [SignalDeepLink] = []
        center.onRevealSource = { revealed.append($0) }
        center.onActivateDeepLink = { linked.append($0) }

        center.activate(event(source: .app(appID: "raven")))

        // Four of the six shipped plugins never set a deep link, so this is
        // the ordinary case, not the edge one.
        #expect(revealed == ["raven"])
        #expect(linked.isEmpty)
    }

    @Test("a deep link still wins, and does not also fire a bare reveal")
    func activatePrefersTheDeepLink() {
        var revealed: [String] = []
        var linked: [SignalDeepLink] = []
        center.onRevealSource = { revealed.append($0) }
        center.onActivateDeepLink = { linked.append($0) }

        let link = SignalDeepLink(appID: "rune", payload: Data("session-7".utf8))
        center.activate(event(source: .app(appID: "rune"), deepLink: link))

        #expect(linked.map(\.appID) == ["rune"])
        #expect(revealed.isEmpty)
    }

    @Test("host and Sage events reveal nothing, because there is no pane to reveal")
    func activateDoesNotInventADestination() {
        var revealed: [String] = []
        center.onRevealSource = { revealed.append($0) }

        center.activate(event(source: .host))
        center.activate(event(source: .sage))

        #expect(revealed.isEmpty)
    }

    @Test("hasDestination is true for any app event, deep link or not")
    func hasDestination() {
        #expect(event(source: .app(appID: "raven")).hasDestination)
        #expect(event(source: .app(appID: "rune"),
                      deepLink: SignalDeepLink(appID: "rune", payload: Data())).hasDestination)
        // The toast falls back to the feed only for these two.
        #expect(!event(source: .host).hasDestination)
        #expect(!event(source: .sage).hasDestination)
    }
}
