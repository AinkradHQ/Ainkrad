import Foundation
import AinkradSignal

/// Which cue an event plays, and whether it plays at all.
///
/// Pure, so every decision here is a table row rather than something you have
/// to hear to verify. The dispatcher holds no policy: if you find yourself
/// adding an `if` about which sound, it belongs here.
enum SignalCue {
    /// `nil` means play nothing.
    static func cue(for event: SignalEvent, rules: RoutingRules) -> UISound? {
        // A per-source choice outranks severity: the user set it deliberately,
        // knowing what that source sounds like.
        switch rules.soundOverride[event.source] {
        case .silent: return nil
        case .named(let name): return UISound(rawValue: name)
        case .bySeverity, .none: break
        @unknown default: break
        }
        // Urgency outranks severity too. "Something is waiting on you" is a
        // different fact from "something broke", and an `.info` event can be
        // the more urgent of the two.
        if event.proposedImportance == .urgent { return .signalUrgent }
        switch event.severity {
        case .failure: return .signalFail
        case .warning: return .signalWarn
        case .info, .success: return .signalArrive
        @unknown default: return .signalArrive
        }
    }
}

extension SignalCue {
    /// Severity as an order. Stated explicitly, not taken from
    /// `CaseIterable`'s index — that is a declaration detail, and letting it
    /// become behaviour means reordering the enum silently changes meaning.
    static func rank(_ severity: SignalSeverity) -> Int {
        switch severity {
        case .info: return 0
        case .success: return 1
        case .warning: return 2
        case .failure: return 3
        @unknown default: return 0
        }
    }
}

/// Collapses a burst of arrivals into one sound.
///
/// Holds ONE timestamp, deliberately. A cache keyed by event or by source is
/// the shape the M3 plan warned against: it suppressed forever and grew
/// without bound. This forgets everything except when it last let a sound
/// through, which is all the question "was that just now?" needs.
struct SignalBurstGate {
    /// Five events landing together is one situation, and hearing it five
    /// times does not make it clearer.
    static let window: TimeInterval = 2

    private var lastAdmitted: Date?
    private var lastRank = -1

    /// Admits when the window has passed, OR when this event is STRICTLY more
    /// severe than the one last heard.
    ///
    /// The severity escape is not a nicety. Without it a warning at t=0
    /// silences a failure at t=0.5, so the burst gate would reliably suppress
    /// exactly the sound worth hearing — the important event muted by the
    /// unimportant one that happened to arrive first. Strictly greater, not
    /// greater-or-equal, so a run of equal failures still collapses to one:
    /// the same reasoning `SignalToastModel` uses to decide which toast a new
    /// arrival may displace.
    mutating func admits(_ now: Date, rank: Int = Int.min) -> Bool {
        if let last = lastAdmitted, now.timeIntervalSince(last) < Self.window,
           rank <= lastRank {
            return false
        }
        lastAdmitted = now
        lastRank = rank
        return true
    }
}
