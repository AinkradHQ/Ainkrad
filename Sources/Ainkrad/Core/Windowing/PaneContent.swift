import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The hosted app, filling the pane.
///
/// Its own view — like `PaneGlassBackdrop`, and for the same measured reason.
/// Inlined in `BlockView.body` it was rebuilt on every focus change, and
/// rebuilding it re-invokes the hosted app's `updateNSView`; for Terminal that
/// reapplies the whole appearance (font, ANSI palette, cursor, transparency) on
/// a tab switch that changed none of it. None of these inputs depend on focus,
/// so SwiftUI compares them, sees them unchanged, and leaves the app alone.
struct PaneContent: View {
    let app: RegisteredApp?
    let topInset: CGFloat
    let fallback: Color
    /// Lets the hosted app say which of its own things this pane is showing, so
    /// a notification can focus the pane that produced it rather than the
    /// first pane of that app.
    ///
    /// Safe to hold here BECAUSE it is memoized per block and `Equatable` by
    /// identity — see `PaneLocatorRegistry.sink(forBlock:)`. A freshly built
    /// closure would compare unequal on every render and undo the whole point
    /// of this view's input list.
    let paneLocator: SignalPaneLocatorSink
    /// `Block.launchGeneration` — a new value remounts the app's root.
    let launchGeneration: Int

    /// Read from the environment rather than taken as an input: it is a plain
    /// `Equatable` value injected one level up in `WorkspacePaneLayer`, so
    /// switching mode invalidates this view without adding a per-render input
    /// that would defeat the memoization this view exists for.
    @Environment(\.ainkradPaneMode) private var paneMode

    var body: some View {
        if let app {
            // The app's own background is painted across the WHOLE pane,
            // including the inset strip, and its root view is inset within it —
            // so the app still looks edge-to-edge (opaque, or
            // translucent-over-blur for terminal transparency) and simply
            // starts a little lower.
            ZStack(alignment: .top) {
                if let fill = app.chromeFill() {
                    fill
                }
                // Generation 11: built FOR the mode, not filtered after the
                // fact. An app that never opted into `AinkradAppModes` falls
                // back to its mode-less factory inside this accessor, so this
                // is unconditional and pre-11 apps are unaffected.
                app.makeRootView(mode: paneMode)
                    .id(launchGeneration)
                    .padding(.top, topInset)
                    .environment(\.ainkradPaneLocator, paneLocator)
            }
        } else {
            fallback
        }
    }
}
