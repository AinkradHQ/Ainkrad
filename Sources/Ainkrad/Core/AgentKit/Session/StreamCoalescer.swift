import Foundation

/// Decides whether a streaming update is due to be published to the UI.
///
/// The transcript previously invalidated SwiftUI once per SSE delta, so the
/// render cost scaled with the model's token rate. This caps publishes at one
/// per `interval` no matter how fast tokens arrive.
///
/// Pure and clock-injected so the behaviour is unit tested without sleeping —
/// a test that waits on real time is slow and flaky, and this decision is
/// simple enough to deserve neither.
struct StreamCoalescer {
    /// 50ms: faster than the eye resolves text appearing, slower than every
    /// provider's token rate, so it bounds invalidations at 20/s.
    static let publishInterval: Duration = .milliseconds(50)

    private let interval: Duration
    private var lastPublish: ContinuousClock.Instant?

    init(interval: Duration = StreamCoalescer.publishInterval) {
        self.interval = interval
    }

    /// True when at least `interval` has elapsed since the last publish (or this
    /// is the first). Mutates: a `true` answer records the publish.
    mutating func shouldPublish(at now: ContinuousClock.Instant) -> Bool {
        guard let lastPublish else {
            self.lastPublish = now
            return true
        }
        guard now - lastPublish >= interval else { return false }
        self.lastPublish = now
        return true
    }

    mutating func reset(at now: ContinuousClock.Instant) {
        lastPublish = nil
        _ = now
    }
}
