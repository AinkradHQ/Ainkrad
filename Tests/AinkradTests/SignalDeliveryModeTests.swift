import Testing
import AinkradSignal
@testable import Ainkrad

@Suite("Signal delivery mode")
struct SignalDeliveryModeTests {
    private let raven = SignalSource.app(appID: "raven")

    @Test("a source nobody has configured is on everything")
    func defaultIsEverything() {
        #expect(SignalDeliveryMode(rules: .default, source: raven) == .everything)
    }

    @Test("feed-only records without interrupting, and reads back as feed-only")
    func feedOnlyRoundTrips() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven)
        #expect(rules.sourceOverrides[raven] == [.feed])
        #expect(!rules.mutedSources.contains(raven))
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .feedOnly)
    }

    @Test("off mutes, and mute outranks any override")
    func offMutes() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        #expect(rules.mutedSources.contains(raven))
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .off)
    }

    @Test("everything clears both the mute and the override")
    func everythingClears() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven)
        SignalDeliveryMode.everything.apply(to: &rules, source: raven)
        #expect(rules.sourceOverrides[raven] == nil)
        #expect(!rules.mutedSources.contains(raven))
    }

    @Test("everything stores no channel set, so evolving defaults still apply")
    func everythingIsNotAFrozenSnapshot() {
        var rules = RoutingRules.default
        SignalDeliveryMode.everything.apply(to: &rules, source: raven)
        // Writing today's full channel set would freeze today's severity table
        // into the user's preferences file for good.
        #expect(rules.sourceOverrides[raven] == nil)
    }

    @Test("each mode changes only the source it names")
    func modesArePerSource() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        #expect(SignalDeliveryMode(rules: rules, source: .host) == .everything)
    }

    @Test("a kind nobody has configured follows its source")
    func kindDefaultsToEverything() {
        #expect(SignalDeliveryMode(rules: .default, source: raven,
                                   kind: "build.failed") == .everything)
    }

    @Test("a kind can be set to feed-only without touching its source")
    func kindFeedOnly() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.warning")
        #expect(rules.sourceKindOverrides[SourceKind(source: raven, kind: "build.warning")]
                == [.feed])
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .everything,
                "muting one kind must not mute the whole app")
        #expect(SignalDeliveryMode(rules: rules, source: raven,
                                   kind: "build.warning") == .feedOnly)
    }

    @Test("off on a kind never mutes the whole source")
    func kindOffDoesNotMuteTheSource() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven, kind: "build.warning")
        // `mutedSources` has no per-kind equivalent and must not be used here:
        // muting the SOURCE to silence one KIND would silence everything else
        // the app says.
        #expect(!rules.mutedSources.contains(raven))
        #expect(SignalDeliveryMode(rules: rules, source: raven,
                                   kind: "build.warning") == .feedOnly)
    }

    @Test("a kind offers two states, because a third would be unreachable")
    func kindOffersTwoStates() {
        // Feed-only is the strongest per-kind setting available, so an "off"
        // segment could never be displayed however the user clicked — a dead
        // control, which is worse than a smaller one.
        #expect(SignalDeliveryMode.kindOptions == [.everything, .feedOnly])
    }

    @Test("everything clears a kind's override")
    func kindEverythingClears() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.warning")
        SignalDeliveryMode.everything.apply(to: &rules, source: raven, kind: "build.warning")
        #expect(rules.sourceKindOverrides.isEmpty)
    }

    @Test("kinds are independent of one another")
    func kindsAreIndependent() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven, kind: "build.warning")
        #expect(SignalDeliveryMode(rules: rules, source: raven,
                                   kind: "build.failed") == .everything)
    }

    @Test("a richer override from a later phase reads as everything, not as broken")
    func unrepresentableOverrideDegradesGracefully() {
        var rules = RoutingRules.default
        rules.sourceOverrides[raven] = [.feed, .badge]
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .everything)
    }
}
