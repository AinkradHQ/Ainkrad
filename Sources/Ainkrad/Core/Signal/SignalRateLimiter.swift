import Foundation
import AinkradSignal

enum RateDecision: Equatable, Sendable {
    case allowed
    case throttled
}

/// A per-source sliding window over event timestamps.
///
/// **Per source, not global**, so one chatty peer cannot silence every other
/// one — a global limiter would let a looping script suppress the failure
/// notification the user actually needed.
///
/// **Pruned on every call**, so a flooding peer is not also a memory leak. The
/// retained timestamps are bounded by the window, never by how long the flood
/// has been running.
///
/// Time is a parameter rather than read from a clock inside, so every branch is
/// a table row in a test instead of a sleep.
@MainActor
final class SignalRateLimiter {
    private let limit: Int
    private let window: TimeInterval
    private var timestamps: [SignalSource: [Date]] = [:]

    init(limit: Int = 20, window: TimeInterval = 10) {
        self.limit = limit
        self.window = window
    }

    /// Records an attempt and says whether it may proceed.
    ///
    /// A throttled attempt is still recorded. That is deliberate: it keeps a
    /// peer that ignores throttling from resetting its own window by
    /// hammering, and it means the count reflects attempts rather than
    /// successes.
    func allow(_ source: SignalSource, now: Date = Date()) -> RateDecision {
        let cutoff = now.addingTimeInterval(-window)
        var recent = (timestamps[source] ?? []).filter { $0 > cutoff }
        let decision: RateDecision = recent.count >= limit ? .throttled : .allowed
        recent.append(now)
        // Cap the retained history at the limit even while throttled, so a
        // sustained flood cannot grow the array between prunes.
        if recent.count > limit { recent.removeFirst(recent.count - limit) }
        timestamps[source] = recent
        return decision
    }

    /// How many timestamps are currently retained for a source. Test-facing:
    /// the bound is the property worth asserting, and it is not observable
    /// through `allow` alone.
    func recordedCount(for source: SignalSource) -> Int {
        timestamps[source]?.count ?? 0
    }
}
