import Testing
import Foundation
import UserNotifications
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Signal banner content")
struct SignalBannerContentTests {
    private func event(_ severity: SignalSeverity = .failure,
                       kind: String = "build.failed",
                       importance: SignalImportance = .normal,
                       dedupeKey: String? = nil,
                       actions: [SignalAction] = [],
                       source: SignalSource = .app(appID: "raven")) -> SignalEvent {
        SignalEvent(source: source, kind: kind, severity: severity,
                    title: "Build failed", body: "3 errors",
                    proposedImportance: importance, actions: actions,
                    dedupeKey: dedupeKey)
    }

    @Test("an urgent event asks the system to break through")
    func urgentIsTimeSensitive() {
        let content = UserNotificationBannerChannel.content(
            for: event(.info, kind: "terminal.agent-attention", importance: .urgent))
        #expect(content.interruptionLevel == .timeSensitive)
    }

    @Test("a normal event is merely active")
    func normalIsActive() {
        #expect(UserNotificationBannerChannel.content(for: event()).interruptionLevel == .active)
    }

    @Test("repeats share a thread, so Notification Center coalesces them too")
    func threadComesFromTheDedupeKey() {
        let content = UserNotificationBannerChannel.content(
            for: event(dedupeKey: "rune.agent:abc:attention"))
        #expect(content.threadIdentifier == "rune.agent:abc:attention")
    }

    @Test("without a dedupe key the thread falls back to source and kind")
    func threadFallsBackToSourceAndKind() {
        let content = UserNotificationBannerChannel.content(for: event())
        #expect(content.threadIdentifier == "app:raven:build.failed")
    }

    @Test("the event id travels so a click can resolve it")
    func carriesTheEventID() {
        let e = event()
        #expect(UserNotificationBannerChannel.content(for: e).userInfo["signalEventID"] as? String
                == e.id.uuidString)
    }

    @Test("at most two actions reach the banner, in declared order")
    func actionsAreCappedAtTwo() {
        let actions = (1...4).map { SignalAction(id: "a\($0)", label: "Action \($0)") }
        let e = event(actions: actions)
        #expect(UserNotificationBannerChannel.bannerActions(for: e).map(\.identifier) == ["a1", "a2"])
    }

    @Test("a destructive action is marked destructive to the system")
    func destructiveIsMarked() {
        let e = event(actions: [SignalAction(id: "delete", label: "Delete", isDestructive: true)])
        let action = try! #require(UserNotificationBannerChannel.bannerActions(for: e).first)
        #expect(action.options.contains(.destructive))
    }

    @Test("an event with no actions claims no category, so no empty button row")
    func noActionsNoCategory() {
        #expect(UserNotificationBannerChannel.content(for: event()).categoryIdentifier.isEmpty)
    }

    @Test("an event with actions is categorised per kind, so buttons match the event")
    func categoryIsPerKind() {
        let e = event(actions: [SignalAction(id: "retry", label: "Retry")])
        #expect(UserNotificationBannerChannel.content(for: e).categoryIdentifier
                == UserNotificationBannerChannel.categoryID(for: e))
        #expect(UserNotificationBannerChannel.categoryID(for: e).contains("build.failed"))
    }
}
