import Foundation
import AinkradAppKit

/// What each open pane last said it is showing.
///
/// The host cannot work this out for itself: a plugin's pane is an opaque
/// SwiftUI view, and `makeRootView(host:)` hands out one `HostServices` per
/// APP rather than per pane. So a pane reports, through the
/// `ainkradPaneLocator` environment sink injected around it, and this holds
/// the answers.
///
/// Values are opaque strings compared only for equality. The host never parses
/// one, which is what keeps a locator from becoming a second payload format
/// that apps then have to agree with the host about.
@MainActor
@Observable
final class PaneLocatorRegistry {
    /// blockID → locator. Keyed by BLOCK, not by app: telling two panes of one
    /// app apart is the entire purpose.
    private var locators: [UUID: String] = [:]

    func set(_ locator: String?, forBlock blockID: UUID) {
        if let locator, !locator.isEmpty {
            locators[blockID] = locator
        } else {
            // A pane reporting nil has nothing addressable on screen any more.
            // Cleared rather than kept, so a notification cannot focus a pane
            // for a session it no longer holds.
            locators[blockID] = nil
        }
    }

    func locator(forBlock blockID: UUID) -> String? { locators[blockID] }

    /// Called when a block closes. Without this the table grows for the
    /// lifetime of the process and a recycled blockID could inherit a stale
    /// locator.
    func forget(blockID: UUID) {
        locators[blockID] = nil
        sinks[blockID] = nil
    }

    // MARK: - Sinks

    /// One sink per block, built once and reused.
    ///
    /// Memoized deliberately. `PaneContent` excludes inputs that would rebuild
    /// the hosted app — a rebuild reapplies a terminal's whole appearance — and
    /// a sink constructed on each render would compare unequal every time and
    /// reintroduce that cost. `SignalPaneLocatorSink` is Equatable by the
    /// identity of its box, so handing back the same instance is what makes
    /// SwiftUI see no change.
    ///
    /// Not stored in `@Observable` state: creating a sink must not invalidate
    /// the view that just asked for one.
    @ObservationIgnored private var sinks: [UUID: SignalPaneLocatorSink] = [:]

    func sink(forBlock blockID: UUID) -> SignalPaneLocatorSink {
        if let existing = sinks[blockID] { return existing }
        // `self` is captured strongly and that is correct: the registry lives
        // on AppEnvironment for the process's lifetime, and a weak capture
        // would silently stop recording locators if the registry were ever
        // rebuilt while panes stayed open.
        let sink = SignalPaneLocatorSink { [self] locator in
            set(locator, forBlock: blockID)
        }
        sinks[blockID] = sink
        return sink
    }

    var trackedCountForTesting: Int { locators.count }
}
