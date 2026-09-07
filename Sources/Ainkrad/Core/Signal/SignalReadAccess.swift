import Foundation
import AinkradSignal

/// A late-filled handle to the feed's read side.
///
/// Exists because of an ordering problem, not because indirection is nice:
/// `signal_search` is assembled in `bootstrapExecutionAndTools`, and the
/// `SignalCenter` it reads is not created until `finalizeBootstrap` — the tool
/// array is consumed before the feed exists. The same shape `SignalEmitterHub`
/// uses for the write side ("built early, gains something to record into
/// later"), applied to reads.
///
/// Holds the center WEAKLY. The environment owns it; a tool outliving the feed
/// must degrade to "no notifications" rather than keep a store alive.
@MainActor
final class SignalReadAccess {
    private weak var center: SignalCenter?

    init() {}

    func attach(_ center: SignalCenter) { self.center = center }

    /// Nil until the feed exists, and again if it ever goes away. Callers must
    /// treat that as "nothing to report", never as an error — a tool that
    /// errors teaches the model to stop calling it.
    var context: SageSignalContext? {
        center.map { SageSignalContext(center: $0) }
    }
}
