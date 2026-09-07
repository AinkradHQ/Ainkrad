import Testing
import Foundation
import AinkradAppKit
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Signal row menu")
struct SignalRowMenuTests {
    private let raven = SignalSource.app(appID: "raven")
    private func event(kind: String = "build.failed") -> SignalEvent {
        SignalEvent(timestamp: Date(timeIntervalSince1970: 0), source: raven,
                    kind: kind, severity: .failure, title: "Build failed",
                    body: "3 errors")
    }
    private func items(_ rules: RoutingRules, isRead: Bool = false,
                       isPinned: Bool = false) -> [AinkradMenuItem] {
        SignalRowMenu.items(for: event(), rules: rules, sourceName: "Raven",
                            isRead: isRead, isPinned: isPinned,
                            onMuteKind: {}, onUnmuteKind: {}, onMuteSource: {},
                            onToggleRead: {}, onCopy: {}, onDismiss: {},
                            onTogglePin: {})
    }

    @Test("the mute item names the source and the kind")
    func muteItemIsSpecific() {
        // "Quiet this" tells the user nothing about what goes quiet. Naming both
        // is the difference between a control they trust and one they avoid.
        #expect(items(.default).map(\.title).contains("Quiet Raven › build.failed"))
    }

    @Test("an already-muted kind offers to unmute instead")
    func mutedKindOffersUnmute() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.failed")
        let titles = items(rules).map(\.title)
        #expect(titles.contains("Alert me about Raven › build.failed"))
        #expect(!titles.contains("Quiet Raven › build.failed"))
    }

    @Test("muting the whole source is offered once, and marked destructive")
    func muteSourceIsMarked() {
        let item = items(.default).first { $0.title == "Turn off everything from Raven" }
        #expect(item?.isDestructive == true)
    }

    @Test("an already-muted source does not offer to mute again")
    func mutedSourceOmitsTheItem() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        #expect(!items(rules).map(\.title).contains("Turn off everything from Raven"))
    }

    @Test("the read item flips with the row's state, both ways")
    func readItemFlips() {
        #expect(items(.default, isRead: false).map(\.title).contains("Mark as read"))
        // Now that `markUnread` exists, triage runs in both directions: a row
        // read by accident can be put back on the pile.
        #expect(items(.default, isRead: true).map(\.title).contains("Mark as unread"))
    }

    @Test("dismiss is offered without a confirmation")
    func dismissIsUnconfirmed() {
        let dismiss = items(.default).first { $0.title == "Dismiss" }
        // One row, out of a log that already evicts by age and by count. A
        // dialog would treat the feed as a filing system rather than a record.
        #expect(dismiss != nil)
        #expect(dismiss?.isDestructive == false)
    }

    @Test("copied text carries when, who, what and the detail")
    func copyText() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let text = SignalRowMenu.clipboardText(for: event(), sourceName: "Raven",
                                               formatter: formatter)
        // The point is pasting a build error into a chat, so the body must be
        // there in full — the row itself clamps it to two lines.
        #expect(text == "[1970-01-01 00:00] Raven · build.failed\nBuild failed\n3 errors")
    }

    @Test("an event with no body copies without a trailing blank line")
    func copyWithoutBody() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let bare = SignalEvent(source: .host, kind: "k", severity: .info, title: "T")
        let text = SignalRowMenu.clipboardText(for: bare, sourceName: "Ainkrad",
                                               formatter: formatter)
        #expect(!text.hasSuffix("\n"))
    }

    @Test("pin flips with state, and sits above the destructive item")
    func pinItem() {
        let titles = items(.default).map(\.title)
        #expect(titles.contains("Pin"))
        #expect(items(.default, isPinned: true).map(\.title).contains("Unpin"))
        // Pin and Dismiss are opposites; the destructive one should not be the
        // first thing under the cursor.
        #expect(titles.firstIndex(of: "Pin")! < titles.firstIndex(of: "Dismiss")!)
    }
}
