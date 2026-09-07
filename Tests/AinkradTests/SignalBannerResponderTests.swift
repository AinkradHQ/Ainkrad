import Testing
import Foundation
import UserNotifications
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Signal banner responder")
final class SignalBannerResponderTests {
    private final class NullDeliverer: SignalDeliverer {
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
    }
    private struct Ctx: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: false, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private let url: URL
    private let center: SignalCenter
    private let deliverer = NullDeliverer()

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        center = SignalCenter(store: try SignalStore(url: url), deliverer: deliverer,
                              contextProvider: Ctx())
        center.retainDeliverer(deliverer)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    private func emit(deepLink: SignalDeepLink? = nil,
                      actions: [SignalAction] = [],
                      from source: SignalSource = .app(appID: "raven")) throws -> SignalEvent {
        center.emit(SignalDraft(kind: "build.failed", severity: .failure,
                                title: "Build failed", deepLink: deepLink, actions: actions),
                    from: source)
        return try #require(center.recent.first)
    }

    @Test("a deep-linked event is marked read and its link followed")
    func followsTheDeepLink() throws {
        var followed: SignalDeepLink?
        center.onActivateDeepLink = { followed = $0 }
        let event = try emit(deepLink: SignalDeepLink(appID: "raven", payload: Data(),
                                                      locator: "session-7"))
        var openedFeed = false
        let responder = SignalBannerResponder(center: center)
        responder.onOpenFeed = { openedFeed = true }

        responder.handle(eventID: event.id.uuidString, actionID: nil)

        #expect(followed?.locator == "session-7")
        #expect(center.readIDs.contains(event.id))
        #expect(openedFeed == false, "it went somewhere; the feed would be a second window")
    }

    @Test("an event with nowhere to go opens the feed rather than nothing")
    func noDeepLinkOpensTheFeed() throws {
        // A HOST event, which is what "nowhere to go" now means. This test
        // used to emit from an app and pass, because an app event without a
        // deep link went nowhere either -- the bug. It now reveals the app,
        // so the feed fallback needs a source that genuinely has no pane.
        let event = try emit(from: .host)
        var openedFeed = false
        let responder = SignalBannerResponder(center: center)
        responder.onOpenFeed = { openedFeed = true }

        responder.handle(eventID: event.id.uuidString, actionID: nil)

        #expect(openedFeed)
        #expect(center.readIDs.contains(event.id))
    }

    @Test("a banner with no deep link reveals its app instead of the feed")
    func noDeepLinkRevealsTheApp() throws {
        let event = try emit()
        var revealed: String?
        var openedFeed = false
        center.onRevealSource = { revealed = $0 }
        let responder = SignalBannerResponder(center: center)
        responder.onOpenFeed = { openedFeed = true }

        responder.handle(eventID: event.id.uuidString, actionID: nil)

        #expect(revealed == "raven")
        #expect(openedFeed == false, "it went somewhere; the feed would be a second window")
    }

    @Test("an evicted event opens the feed instead of doing nothing")
    func evictedEventOpensTheFeed() {
        var openedFeed = false
        let responder = SignalBannerResponder(center: center)
        responder.onOpenFeed = { openedFeed = true }
        responder.handle(eventID: UUID().uuidString, actionID: nil)
        #expect(openedFeed)
    }

    @Test("a malformed identifier opens the feed and does not crash")
    func malformedIDOpensTheFeed() {
        var openedFeed = false
        let responder = SignalBannerResponder(center: center)
        responder.onOpenFeed = { openedFeed = true }
        responder.handle(eventID: "not-a-uuid", actionID: nil)
        #expect(openedFeed)
    }

    @Test("a chosen action runs, and does not also follow the deep link")
    func actionRunsInsteadOfActivating() throws {
        var invoked: SignalAction?
        var followed = false
        center.onInvokeAction = { _, action in invoked = action }
        center.onActivateDeepLink = { _ in followed = true }
        let event = try emit(deepLink: SignalDeepLink(appID: "raven", payload: Data()),
                             actions: [SignalAction(id: "retry", label: "Retry")])

        SignalBannerResponder(center: center)
            .handle(eventID: event.id.uuidString, actionID: "retry")

        #expect(invoked?.id == "retry")
        #expect(followed == false, "the user picked a button, not the banner body")
        #expect(center.readIDs.contains(event.id))
    }

    @Test("an unknown action id falls back to activating, not to silence")
    func unknownActionFallsBack() throws {
        var followed = false
        center.onActivateDeepLink = { _ in followed = true }
        let event = try emit(deepLink: SignalDeepLink(appID: "raven", payload: Data()),
                             actions: [SignalAction(id: "retry", label: "Retry")])

        SignalBannerResponder(center: center)
            .handle(eventID: event.id.uuidString, actionID: "gone")

        #expect(followed)
    }

    @Test("swiping the banner away marks it read without opening a window")
    func dismissMarksReadOnly() throws {
        var openedFeed = false
        var followed = false
        center.onActivateDeepLink = { _ in followed = true }
        let event = try emit(deepLink: SignalDeepLink(appID: "raven", payload: Data()))
        let responder = SignalBannerResponder(center: center)
        responder.onOpenFeed = { openedFeed = true }

        responder.handle(eventID: event.id.uuidString,
                         actionID: UNNotificationDismissActionIdentifier)

        #expect(center.readIDs.contains(event.id))
        #expect(openedFeed == false)
        #expect(followed == false, "dismissing is not a request to go anywhere")
    }

    @Test("reading an event reports it, so its banner can be withdrawn")
    func readingReportsForWithdrawal() throws {
        var withdrawn: [UUID] = []
        center.onRead = { withdrawn.append(contentsOf: $0) }
        let event = try emit()

        center.markRead(ids: [event.id])

        #expect(withdrawn == [event.id])
    }
}
