import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Signal cue selection")
struct SignalCueTests {
    private let raven = SignalSource.app(appID: "raven")
    private func event(_ severity: SignalSeverity,
                       importance: SignalImportance = .normal,
                       source: SignalSource? = nil) -> SignalEvent {
        SignalEvent(source: source ?? raven, kind: "k", severity: severity,
                    title: "t", proposedImportance: importance)
    }

    @Test("severity picks the cue when nothing else applies")
    func severityDefaults() {
        #expect(SignalCue.cue(for: event(.failure), rules: .default) == .signalFail)
        #expect(SignalCue.cue(for: event(.warning), rules: .default) == .signalWarn)
        #expect(SignalCue.cue(for: event(.success), rules: .default) == .signalArrive)
        #expect(SignalCue.cue(for: event(.info), rules: .default) == .signalArrive)
    }

    @Test("urgency outranks severity, even for an informational event")
    func urgencyWins() {
        // "Something is waiting on you" is a different fact from "something
        // broke", and an .info event can be the more urgent of the two.
        #expect(SignalCue.cue(for: event(.info, importance: .urgent),
                              rules: .default) == .signalUrgent)
    }

    @Test("a per-source silent choice outranks everything")
    func silentWins() {
        var rules = RoutingRules.default
        rules.soundOverride[raven] = .silent
        #expect(SignalCue.cue(for: event(.failure, importance: .urgent), rules: rules) == nil)
    }

    @Test("a named cue outranks severity")
    func namedWins() {
        var rules = RoutingRules.default
        rules.soundOverride[raven] = .named(UISound.confirm.rawValue)
        #expect(SignalCue.cue(for: event(.failure), rules: rules) == .confirm)
    }

    @Test("a named cue the host does not know plays nothing rather than guessing")
    func unknownNameIsSilent() {
        var rules = RoutingRules.default
        rules.soundOverride[raven] = .named("not-a-cue")
        #expect(SignalCue.cue(for: event(.failure), rules: rules) == nil)
    }

    @Test("an override on one source does not affect another")
    func overrideIsPerSource() {
        var rules = RoutingRules.default
        rules.soundOverride[raven] = .silent
        #expect(SignalCue.cue(for: event(.failure, source: .host), rules: rules) == .signalFail)
    }
}

@MainActor
@Suite("Signal burst gate")
struct SignalBurstGateTests {
    // `admits` is mutating, and `#expect` wraps its argument in a closure
    // where the value is immutable — so every call is hoisted into a local
    // first rather than inlined into the macro.
    @Test("a burst plays once")
    func burstPlaysOnce() {
        var gate = SignalBurstGate()
        let start = Date()
        let first = gate.admits(start)
        let during = gate.admits(start.addingTimeInterval(0.1))
        let late = gate.admits(start.addingTimeInterval(1.9))
        #expect(first)
        // Five events landing together is one situation; hearing it five times
        // does not make it clearer.
        #expect(!during)
        #expect(!late)
    }

    @Test("after the window, the next arrival is heard again")
    func windowReopens() {
        var gate = SignalBurstGate()
        let start = Date()
        let first = gate.admits(start)
        let reopened = gate.admits(start.addingTimeInterval(2.0))
        #expect(first)
        #expect(reopened)
    }

    @Test("the gate holds one timestamp, not a growing cache")
    func gateIsStateless() {
        // The M3 plan warned against a suppression cache keyed by event: it
        // suppressed forever and grew per key. This forgets everything except
        // when it last let a sound through.
        var gate = SignalBurstGate()
        let start = Date()
        for i in 0..<1000 { _ = gate.admits(start.addingTimeInterval(Double(i) * 0.001)) }
        let muchLater = gate.admits(start.addingTimeInterval(10))
        #expect(muchLater)
    }

    @Test("a MORE severe event is heard even inside the window")
    func severityBreaksThrough() {
        var gate = SignalBurstGate()
        let start = Date()
        let warning = gate.admits(start, rank: SignalCue.rank(.warning))
        let failure = gate.admits(start.addingTimeInterval(0.5),
                                  rank: SignalCue.rank(.failure))
        #expect(warning)
        // Without this, a warning at t=0 silences a failure at t=0.5 — the
        // burst gate would reliably suppress exactly the sound worth hearing.
        #expect(failure)
    }

    @Test("a less severe event inside the window stays suppressed")
    func lesserStaysQuiet() {
        var gate = SignalBurstGate()
        let start = Date()
        let failure = gate.admits(start, rank: SignalCue.rank(.failure))
        let info = gate.admits(start.addingTimeInterval(0.5), rank: SignalCue.rank(.info))
        #expect(failure)
        #expect(!info)
    }

    @Test("a run of equal failures still collapses to one")
    func equalSeverityCollapses() {
        var gate = SignalBurstGate()
        let start = Date()
        let first = gate.admits(start, rank: SignalCue.rank(.failure))
        let second = gate.admits(start.addingTimeInterval(0.5),
                                 rank: SignalCue.rank(.failure))
        // Strictly greater, not greater-or-equal — the same rule
        // `SignalToastModel` uses for which toast may displace which.
        #expect(first)
        #expect(!second)
    }
}
