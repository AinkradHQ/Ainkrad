import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Source status line")
struct SourceStatusLineTests {
    private let raven = SignalSource.app(appID: "raven")
    private let rune = SignalSource.app(appID: "rune")

    private func activity(_ kind: String, _ count: Int) -> SignalKindActivity {
        SignalKindActivity(kind: kind, count: count, lastSeen: Date(), source: raven)
    }

    @Test("a source at its defaults says nothing extra")
    func defaultsAreSilent() {
        // A row that always carries a line teaches the user to stop reading it.
        #expect(SourceStatusLine.text(rules: .default, source: raven) == nil)
    }

    @Test("the source's own delivery mode is never restated")
    func neverRestatesTheMode() {
        // The picker beside it already shows this. Saying it twice is what let
        // three controls disagree about one value.
        var off = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &off, source: raven)
        #expect(SourceStatusLine.text(rules: off, source: raven) == nil)

        var quiet = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &quiet, source: raven)
        #expect(SourceStatusLine.text(rules: quiet, source: raven) == nil)
    }

    @Test("quiet kinds are counted, and counted only for this source")
    func countsQuietKinds() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "a")
        #expect(SourceStatusLine.text(rules: rules, source: raven) == "1 kind quiet")

        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "b")
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: rune, kind: "c")
        #expect(SourceStatusLine.text(rules: rules, source: raven) == "2 kinds quiet")
        #expect(SourceStatusLine.text(rules: rules, source: rune) == "1 kind quiet")
    }

    @Test("a floor, a cue and a bypass each show, in a stable order")
    func showsEveryOverride() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "a")
        rules.interruptFloor[raven] = .failure
        rules.soundOverride[raven] = .silent
        rules.urgentBypass.insert(raven)
        #expect(SourceStatusLine.text(rules: rules, source: raven)
                == "1 kind quiet · failures only · silent · urgent bypasses Focus")
    }

    @Test("the default cue is not worth mentioning")
    func bySeverityIsSilentInTheLine() {
        var rules = RoutingRules.default
        rules.soundOverride[raven] = .bySeverity
        #expect(SourceStatusLine.text(rules: rules, source: raven) == nil)
    }

    @Test("the loudest kind shows only once it is actually loud")
    func loudestIsThresholded() {
        // A source whose loudest kind fired twice does not have a noise
        // problem. Labelling it as though it does trains the user to ignore
        // this line on the day a source really is shouting.
        let quiet = activity("build.failed", SourceStatusLine.loudEnough - 1)
        #expect(SourceStatusLine.text(rules: .default, source: raven, loudest: quiet) == nil)

        let loud = activity("build.failed", 19)
        #expect(SourceStatusLine.text(rules: .default, source: raven, loudest: loud)
                == "loudest build.failed ×19")
    }

    @Test("the floor is worded the same way the control words it")
    func floorWordingMatches() {
        // Two different phrasings for one setting reads as two settings.
        #expect(SignalSeverity.warning.floorLabel == "Warnings and failures")
        #expect(SignalSeverity.warning.floorSummary == "warnings and failures")
    }
}

@MainActor
@Suite("Sources the settings pane lists")
struct SignalSettingsSourcesTests {
    private let raven = SignalSource.app(appID: "raven")
    private let rune = SignalSource.app(appID: "rune")

    @Test("nothing configured names nothing")
    func empty() {
        #expect(SignalSettingsPane.configuredSources(in: .default).isEmpty)
    }

    @Test("every rule that names a source contributes it")
    func everyRuleContributes() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: rune, kind: "session.failed")
        #expect(SignalSettingsPane.configuredSources(in: rules) == [raven, rune])
    }

    @Test("a floor, a cue or a bypass alone is enough to be listed")
    func quietConfiguration() {
        // Each of these is a setting the user made and must be able to find
        // again, even for a source that has never emitted.
        var rules = RoutingRules.default
        rules.interruptFloor[raven] = .warning
        #expect(SignalSettingsPane.configuredSources(in: rules) == [raven])

        var cue = RoutingRules.default
        cue.soundOverride[rune] = .silent
        #expect(SignalSettingsPane.configuredSources(in: cue) == [rune])

        var bypass = RoutingRules.default
        bypass.urgentBypass.insert(raven)
        #expect(SignalSettingsPane.configuredSources(in: bypass) == [raven])
    }
}

@MainActor
@Suite("Notification vocabulary")
struct SignalVocabularyTests {
    private let raven = SignalSource.app(appID: "raven")

    @Test("the three delivery states read Alert, Quiet, Off")
    func deliveryLabels() {
        // One ladder, three words, used in every surface. "Feed only" described
        // the mechanism; "Quiet" describes what the user gets, and stops the
        // "it is still in the feed" hint having to be printed beside every
        // control that can silence something.
        #expect(SignalDeliveryMode.everything.label == "Alert")
        #expect(SignalDeliveryMode.feedOnly.label == "Quiet")
        #expect(SignalDeliveryMode.off.label == "Off")
    }

    @Test("the row menu speaks the same three words")
    func rowMenuVocabulary() {
        let event = SignalEvent(timestamp: Date(timeIntervalSince1970: 0), source: raven,
                                kind: "build.failed", severity: .failure,
                                title: "Build failed", body: nil)
        func titles(_ rules: RoutingRules) -> [String] {
            SignalRowMenu.items(for: event, rules: rules, sourceName: "Raven",
                                isRead: false, isPinned: false,
                                onMuteKind: {}, onUnmuteKind: {}, onMuteSource: {},
                                onToggleRead: {}, onCopy: {}, onDismiss: {},
                                onTogglePin: {}).map(\.title)
        }
        #expect(titles(.default).contains("Quiet Raven › build.failed"))
        #expect(titles(.default).contains("Turn off everything from Raven"))

        var quieted = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &quieted, source: raven, kind: "build.failed")
        #expect(titles(quieted).contains("Alert me about Raven › build.failed"))
    }

    @Test("no surface reintroduces a fourth word for silence")
    func noStrayVerbs() {
        // The feature used to carry seven: mute, unmute, muted, silence, off,
        // feed only, turn back on. A regression here is a user reading two
        // words for one state and assuming they are two states.
        let event = SignalEvent(timestamp: Date(timeIntervalSince1970: 0), source: raven,
                                kind: "build.failed", severity: .failure,
                                title: "Build failed", body: nil)
        let titles = SignalRowMenu.items(
            for: event, rules: .default, sourceName: "Raven",
            isRead: false, isPinned: false,
            onMuteKind: {}, onUnmuteKind: {}, onMuteSource: {},
            onToggleRead: {}, onCopy: {}, onDismiss: {}, onTogglePin: {}).map(\.title)
        #expect(!titles.contains { $0.lowercased().contains("mute") })
        #expect(!titles.contains { $0.lowercased().contains("silence") })
    }
}

@MainActor
@Suite("Snooze")
struct SignalSnoozeTests {
    @Test("exactly two options, offered identically everywhere")
    func twoOptions() {
        // The dropdown offered one hour, Settings offered two choices and the
        // overlay offered none. Same action, three surfaces, three answers.
        #expect(SignalSnooze.allCases.count == 2)
        #expect(SignalSnooze.allCases.map(\.label)
                == ["Quiet for an hour", "Quiet until tomorrow"])
    }

    @Test("an hour is an hour")
    func anHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SignalSnooze.hour.until(after: now) == now.addingTimeInterval(3600))
    }

    @Test("until tomorrow means the working morning, not midnight")
    func tomorrowMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 3, hour: 23))!

        let resume = SignalSnooze.tomorrow.until(after: now, calendar: calendar)

        // Midnight would end it an hour later, in the middle of the night —
        // which is not what anyone means by "until tomorrow".
        let parts = calendar.dateComponents([.day, .hour], from: resume)
        #expect(parts.day == 4)
        #expect(parts.hour == 8)
    }

    @Test("applying a snooze writes the same field quiet hours reads")
    func appliesToSuppression() {
        var suppression = SuppressionWindow()
        let now = Date(timeIntervalSince1970: 1_000_000)
        SignalSnooze.hour.apply(to: &suppression, at: now)
        #expect(suppression.isSuppressing(at: now))
        #expect(!suppression.isSuppressing(at: now.addingTimeInterval(3601)))
    }

    @Test("lifting a snooze leaves the schedule alone")
    func liftKeepsSchedule() {
        // A user ending an ad-hoc quiet spell has not asked to be woken at 3am.
        var suppression = SuppressionWindow(quietStartMinute: 22 * 60,
                                            quietEndMinute: 7 * 60)
        SignalSnooze.tomorrow.apply(to: &suppression, at: Date())
        SignalSnooze.lift(&suppression)
        #expect(suppression.snoozedUntil == nil)
        #expect(suppression.quietStartMinute == 22 * 60)
        #expect(suppression.quietEndMinute == 7 * 60)
    }
}

@MainActor
@Suite("Feed view state")
struct SignalViewStateFilterTests {
    private let raven = SignalSource.app(appID: "raven")

    @Test("the chip count ignores the rail's source selection")
    func chipCountExcludesSource() {
        // The rail has its own always-visible control. Counting it would make
        // the Filters button claim a filter the user can already see is set.
        var state = SignalViewState(selectedSource: raven)
        #expect(state.chipFilterCount == 0)
        state.severities = [.failure, .warning]
        state.unreadOnly = true
        #expect(state.chipFilterCount == 3)
    }

    @Test("grouping by app is impossible once a source is selected")
    func groupingCollapsesUnderASourceFilter() {
        // Every event would be from that source, so the grouped list is one
        // group whose header names what the rail already names.
        var state = SignalViewState(grouping: .bySource)
        #expect(state.canGroupBySource)
        #expect(state.effectiveGrouping == .bySource)

        state.selectedSource = raven
        #expect(!state.canGroupBySource)
        #expect(state.effectiveGrouping == .byTime)
    }

    @Test("the stored grouping survives a source filter and comes back")
    func groupingIsNotRewritten() {
        // Silently rewriting the preference would lose a choice the user made
        // deliberately, and they would have to make it again every time they
        // looked at one app.
        var state = SignalViewState(grouping: .bySource, selectedSource: raven)
        #expect(state.effectiveGrouping == .byTime)
        #expect(state.grouping == .bySource)

        state.selectedSource = nil
        #expect(state.effectiveGrouping == .bySource)
    }
}

@MainActor
@Suite("Feed overlay sizing")
struct SignalFeedOverlaySizingTests {
    @Test("it grows with the window instead of sitting at 820x560")
    func scalesWithTheWindow() {
        // The feed's chief job is reading a build error, which is the payload
        // that needs height. A fixed box meant expanding a row scrolled rather
        // than revealed, however much screen was going spare.
        let small = CGSize(width: 1280, height: 800)
        let large = CGSize(width: 2560, height: 1440)
        #expect(SignalFeedOverlayView.height(in: large)
                > SignalFeedOverlayView.height(in: small))
        #expect(SignalFeedOverlayView.width(in: large)
                > SignalFeedOverlayView.width(in: small))
    }

    @Test("it never shrinks below the point the rail stops fitting")
    func hasAFloor() {
        let tiny = CGSize(width: 600, height: 300)
        #expect(SignalFeedOverlayView.width(in: tiny) == 720)
        #expect(SignalFeedOverlayView.height(in: tiny) == 480)
    }

    @Test("it never grows past a readable line length")
    func hasACeiling() {
        // Past this a line of body text is too long to track back to the start
        // of the next one.
        let huge = CGSize(width: 6016, height: 3384)
        #expect(SignalFeedOverlayView.width(in: huge) == 1100)
        #expect(SignalFeedOverlayView.height(in: huge) == 900)
    }
}
