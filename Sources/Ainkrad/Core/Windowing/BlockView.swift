import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AinkradAppKit
import AinkradHostRuntime

/// One pane: a floating, rounded panel over the sky holding the hosted app
/// content edge-to-edge. Deliberately chromeless — no title bar, no app
/// name/icon, no close or magnify button, no separator line: the pane IS the
/// app, and focus is already legible from the targeting brackets, accent glow
/// and the dimming of unfocused panes. Closing is ⌘W (or the context menu, or
/// a Focus-Mode tab's ×); zooming is ⌘M.
///
/// Strictly tiled in the balanced grid (no overlap or z-order). Termius-style
/// rearranging survives the chrome removal through a grab strip along the
/// pane's top edge that is invisible at rest and shows a grabber on hover:
/// drag it over another pane to change position (the grid reflows live).
struct BlockView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let block: Block
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry
    var workspace: Workspace?
    /// The pane's exact pixel size, supplied by the layout (see
    /// `paneGeometry`). Feeding it in directly — rather than reading it back
    /// through a preference key — keeps the drop delegate's edge math from
    /// ever seeing a stale zero size (which would force every drop to the
    /// `.trailing` fallback, making perpendicular splits impossible).
    var paneSize: CGSize = .zero

    @State private var hasArrived = false
    @State private var isHoveringGrabber = false
    @State private var dropEdge: PaneEdge?

    private var app: RegisteredApp? {
        registry.allApps.first { $0.id == block.appID }
    }

    private var isFocused: Bool {
        tileLayout.focusedBlockID == block.id
    }

    /// The pane is translucent when its app declares a sub-opaque window fill
    /// (Sage opacity slider, Terminal scheme opacity, Git Mage transparency).
    private var isTranslucentPane: Bool {
        guard let fill = app?.chromeFill() else { return false }
        return NSColor(fill).alphaComponent < 1
    }

    /// Render the host's blurred sky+island behind this pane only when the app's
    /// blur is enabled AND the pane is translucent (otherwise the pane content
    /// covers it — rendering would be wasted, and there'd be nothing to reveal).
    private var glassBlur: Bool {
        environment.appAppearanceStore.blurEnabled(block.appID) && isTranslucentPane
    }

    private var isInFocusMode: Bool {
        workspace?.viewMode == .focus
    }

    /// True while this pane's header drag session is live — it "lifts":
    /// dims and shrinks slightly until dropped or released.
    private var isBeingDragged: Bool {
        tileLayout.draggingBlockID == block.id
    }

    private var paneOpacity: Double {
        if isBeingDragged { return 0.45 }
        return isFocused ? 1 : 0.92
    }

    private var paneScale: CGFloat {
        if !hasArrived && !reduceMotion { return 0.97 }
        return isBeingDragged ? 0.98 : 1
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        return PaneContent(app: app, topInset: contentTopInset, fallback: tokens.surface,
                           paneLocator: environment.paneLocators.sink(forBlock: block.id))
            .overlay(alignment: .top) { grabStrip(tokens: tokens) }
        // The pane body is clear, so a translucent app (Terminal scheme
        // opacity, Git Mage transparency, Sage opacity) reveals whatever
        // sits behind it: the shared sharp workspace backdrop by default, or —
        // when this app's blur is enabled — the host-rendered Gaussian blur
        // below. A view can't blur the layers behind it, so the host draws its
        // own sky+island copy here and blurs that. It sits behind the whole
        // pane, so everything in it frosts continuously (no seam).
        // Extracted into its own view on purpose — see `PaneGlassBackdrop`. Its
        // only input is whether the blur is on, which does NOT change when focus
        // moves, so SwiftUI skips re-rendering it on a tab switch.
        .background(PaneGlassBackdrop(isEnabled: glassBlur))
        .clipShape(ChamferShape(cut: AinkradRadius.md))
        // The pane's frame — and, when it becomes the focused one, the pulse of
        // light that now carries the tab transition. Its own view so the pulse
        // animates without re-evaluating this body (and therefore without
        // touching the app's content or the blurred backdrop) on every frame.
        .overlay(PaneActivationRing(isFocused: isFocused, tokens: tokens))
        .overlay(dropZoneHighlight(tokens: tokens))
        .shadow(color: isFocused ? tokens.accentPrimary.opacity(0.28) : .black.opacity(0.25), radius: isFocused ? 22 : 12)
        .opacity(paneOpacity)
        .scaleEffect(paneScale)
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
        // Clicking a Focus-Mode tab focuses the pane; this hands the KEYBOARD
        // to the app inside it, so the terminal that just came forward is
        // typeable without a second click.
        .background(PaneKeyFocusAnchor(isFocused: isFocused))
        .animation(.easeOut(duration: 0.15), value: isBeingDragged)
        // When the drag session ends (drop landed elsewhere, or released
        // over no target), drop any lingering preview highlight — SwiftUI
        // doesn't reliably call dropExited on panes the drag merely passed
        // over, so this is the guaranteed clear.
        .onChange(of: tileLayout.draggingBlockID) { _, newValue in
            if newValue == nil { dropEdge = nil }
        }
        .onDrop(of: [.text], delegate: PaneEdgeDropDelegate(
            targetBlockID: block.id,
            tileLayout: tileLayout,
            size: { paneSize },
            edge: $dropEdge
        ))
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.1), value: dropEdge)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.15)) { hasArrived = true }
        }
    }

    /// The half of this pane the dragged pane would occupy — a live drop
    /// preview in the targeting language: accent wash, corner brackets,
    /// and a split-direction glyph, animating between edges as the drag
    /// moves.
    @ViewBuilder
    private func dropZoneHighlight(tokens: DesignTokens) -> some View {
        // A drop preview only means anything while a drag is in flight —
        // gating on the live drag flag (which every render observes)
        // guarantees the highlight vanishes the instant the drag ends, even
        // if a stale `dropEdge` lingers from a pane the drag passed over.
        if let dropEdge, tileLayout.draggingBlockID != nil {
            let isHorizontal = dropEdge == .leading || dropEdge == .trailing
            let zone = ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentPrimary.opacity(0.16))
                .overlay(
                    ChamferShape(cut: AinkradRadius.sm)
                        .strokeBorder(tokens.accentSecondary.opacity(0.65), lineWidth: 1)
                )
                .overlay(
                    TargetingBrackets(length: 9)
                        .stroke(tokens.accentSecondary.opacity(0.9), lineWidth: 1.5)
                        .padding(4)
                )
                .overlay(
                    Image(systemName: isHorizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.85))
                        .shadow(color: tokens.accentSecondary.opacity(0.8), radius: 6)
                )
                .padding(3)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            Group {
                switch dropEdge {
                case .leading:
                    zone.frame(width: max(paneSize.width / 2, 0)).frame(maxWidth: .infinity, alignment: .leading)
                case .trailing:
                    zone.frame(width: max(paneSize.width / 2, 0)).frame(maxWidth: .infinity, alignment: .trailing)
                case .top:
                    zone.frame(height: max(paneSize.height / 2, 0)).frame(maxHeight: .infinity, alignment: .top)
                case .bottom:
                    zone.frame(height: max(paneSize.height / 2, 0)).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Grab strip

    /// The pane's only chrome: a slim strip along the top edge that is
    /// completely invisible at rest and, on hover, fades in a small grabber
    /// pill. It exists to keep drag-to-rearrange after the header was removed —
    /// deleting the header outright would have silently deleted the only way to
    /// move a pane in the grid, and the context menu has no "move".
    ///
    /// Its height matches `contentTopInset` wherever there is one, so on those
    /// panes the strip sits entirely in the padding and steals no clicks from
    /// the app. Where there is no inset it falls back to a minimum height and
    /// does overlay the app's top edge — the price of keeping drag.
    private func grabStrip(tokens: DesignTokens) -> some View {
        Color.clear
            .frame(height: max(contentTopInset, 10))
            .overlay {
                Capsule()
                    .fill(tokens.foreground.opacity(isHoveringGrabber ? 0.35 : 0))
                    .frame(width: 34, height: 3)
            }
            .contentShape(Rectangle())
            .onHover { isHoveringGrabber = $0 }
            .animation(.easeOut(duration: 0.12), value: isHoveringGrabber)
            .onDrag {
                tileLayout.focus(block.id)
                tileLayout.draggingBlockID = block.id
                return NSItemProvider(object: block.id.uuidString as NSString)
            } preview: {
                // Termius-style drag ghost: a small pill, not the whole pane.
                HStack(spacing: 6) {
                    paneTile(tokens: tokens)
                    Text(block.displayTitle(appName: app?.displayName))
                        .font(AinkradFont.display(11, weight: .medium))
                        .foregroundStyle(tokens.foreground)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tokens.surfaceElevated)
                .clipShape(Capsule())
            }
            .help("Drag to rearrange")
            // The pane menu used to hang off the header. It moves here rather
            // than onto the whole pane: the pane body belongs to the hosted app,
            // which has its own right-click menus (Hoard's row menu, text
            // fields), and a host menu covering all of it would shadow them.
            .ainkradContextMenu(blockMenuItems)
    }

    /// The pane's right-click actions, in HUD form.
    private var blockMenuItems: [AinkradMenuItem] {
        var items: [AinkradMenuItem] = [
            AinkradMenuItem(title: "Split Right", systemName: "rectangle.righthalf.inset.filled") {
                tileLayout.split(block.id, edge: .trailing)
            },
            AinkradMenuItem(title: "Split Down", systemName: "rectangle.bottomhalf.inset.filled") {
                tileLayout.split(block.id, edge: .bottom)
            },
            AinkradMenuItem(title: "Duplicate", systemName: "plus.square.on.square") {
                tileLayout.duplicate(block.id)
            },
        ]
        if let workspace {
            items.append(AinkradMenuItem(
                title: isInFocusMode ? "Back to Split Mode" : "Focus Mode",
                systemName: isInFocusMode ? "rectangle.split.2x2" : "rectangle.inset.filled"
            ) {
                tileLayout.focus(block.id)
                workspace.viewMode = isInFocusMode ? .split : .focus
                environment.sounds.play(.focusMode)
            })
        }
        items.append(AinkradMenuItem(title: "Reset Layout", systemName: "arrow.counterclockwise") {
            tileLayout.resetLayout()
        })
        items.append(AinkradMenuItem(title: "Close", systemName: "xmark", isDestructive: true) {
            environment.sounds.play(.appClose)
            tileLayout.close(block.id)
        })
        return items
    }

    /// The app's neon tile at HUD size, drawn live from the active theme and
    /// matching the Launcher rows. Only the drag ghost uses it now that the
    /// pane header is gone.
    private func paneTile(tokens: DesignTokens) -> some View {
        NeonAppTile(symbol: app?.icon ?? "app", tokens: tokens, size: 18)
    }

    // MARK: - Content

    /// Breathing room between the pane's top edge and the app's first line.
    /// The removed header used to provide it; without it a terminal's prompt sat
    /// hard against the border.
    ///
    /// Applied only when the app declares a window fill, because that fill is
    /// what paints the inset strip — the same color and opacity as the app's own
    /// background, so it reads as the app having padding rather than as a gap.
    /// An app that declares no fill paints its own background edge-to-edge and
    /// the host cannot know its color; insetting it would open a visible band of
    /// workspace backdrop above it. Those apps (Sage, Hoard, Settings) lay out
    /// their own interior padding, which is why this is a terminal-shaped
    /// problem in the first place.
    private var contentTopInset: CGFloat {
        app?.chromeFill() == nil ? 0 : 12
    }
}

/// The pane's border and targeting brackets — and the activation pulse that
/// replaced the content cross-fade as the tab transition.
///
/// When this pane becomes the focused one its accent border flares to full
/// strength and thickens slightly, then settles back over ~320ms, and the
/// brackets snap in. The effect is that the pane you switched to visibly "comes
/// alive" — motion the eye can follow — while the content underneath it never
/// changes opacity, so nothing flashes and no two terminals ever ghost through
/// each other.
///
/// Strokes only, and no shadow: a 1px path costs nothing to animate, where the
/// shadow this file used to animate was an offscreen render pass per frame.
private struct PaneActivationRing: View {
    let isFocused: Bool
    let tokens: DesignTokens

    @Environment(\.ainkradReduceMotion) private var reduceMotion
    /// 1 at the instant of activation, easing to 0. Drives both the border's
    /// brightness and its width, so the flare reads as light rather than as the
    /// frame changing size.
    @State private var pulse: Double = 0

    var body: some View {
        ZStack {
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(borderColor, lineWidth: 1 + pulse * 0.6)

            TargetingBrackets(length: 10)
                .stroke(bracketColor, lineWidth: 1.5)
                .padding(-2)
        }
        .onChange(of: isFocused) { _, focused in
            guard focused, !reduceMotion else { return }
            // Set the start value, then animate to rest on the next tick, so
            // the flare actually renders at full strength before it decays.
            pulse = 1
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.32)) { pulse = 0 }
            }
        }
    }

    private var borderColor: Color {
        guard isFocused else { return tokens.foreground.opacity(0.1) }
        return tokens.accentPrimary.opacity(0.55 + 0.45 * pulse)
    }

    private var bracketColor: Color {
        guard isFocused else { return .clear }
        return tokens.accentSecondary.opacity(0.85)
    }
}

/// The hosted app, filling the pane.
///
/// Its own view — like `PaneGlassBackdrop`, and for the same measured reason.
/// Inlined in `BlockView.body` it was rebuilt on every focus change, and
/// rebuilding it re-invokes the hosted app's `updateNSView`; for Terminal that
/// reapplies the whole appearance (font, ANSI palette, cursor, transparency) on
/// a tab switch that changed none of it. None of these inputs depend on focus,
/// so SwiftUI compares them, sees them unchanged, and leaves the app alone.
private struct PaneContent: View {
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
                app.makeRootView()
                    .padding(.top, topInset)
                    .environment(\.ainkradPaneLocator, paneLocator)
            }
        } else {
            fallback
        }
    }
}

/// The host-rendered Gaussian blur revealed through a translucent pane.
///
/// A view can't blur the layers behind it, so the host draws its own sky+island
/// copy here and blurs that. It sits behind the whole pane, so everything in it
/// frosts continuously (no seam).
///
/// ## Why this is its own view and not a `.background { }` closure
///
/// It used to be inlined in `BlockView.body`, which meant every focus change
/// re-evaluated it — and re-rasterized its `drawingGroup`. Measured, a single
/// tab switch rebuilt this backdrop five times and stalled the main thread for
/// up to 184ms (~11 dropped frames), while an idle app drifted 0.9ms. The blur
/// does not depend on focus at all, so as a separate view with one `Bool` input
/// SwiftUI compares that input, sees it unchanged, and skips the whole subtree.
private struct PaneGlassBackdrop: View {
    let isEnabled: Bool

    var body: some View {
        if isEnabled {
            ZStack {
                // `isLive: false` — this copy exists only to be blurred at
                // radius 26, where 30fps starfield drift is not perceptible.
                // Each blurred pane was running its own full live sky (~570
                // Scry fills + 18 radial gradients per frame), so three
                // translucent panes cost four live skies to render one visible
                // one. The real sky behind the workspace still animates;
                // nothing the user can actually see stopped moving.
                AmbientSkyView(isLive: false)
                FloatingIslandView()
                    .frame(maxWidth: 860, maxHeight: 574)
            }
            .blur(radius: 26)
            // The blurred backdrop is a pure function of theme + geometry now
            // that it no longer animates, so let the compositor cache it as one
            // texture instead of re-rasterizing the whole stack on every
            // unrelated pane invalidation.
            .drawingGroup()
        }
    }
}

/// The Termius drop mechanism: while a dragged pane hovers, the nearest
/// half of this pane is tracked (for the highlight); dropping performs
/// `TileLayout.move` — joining as an equal sibling on parallel edges, or
/// wrapping this pane into a stacked pair on perpendicular ones.
private struct PaneEdgeDropDelegate: DropDelegate {
    let targetBlockID: UUID
    let tileLayout: TileLayout
    let size: () -> CGSize
    @Binding var edge: PaneEdge?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging = tileLayout.draggingBlockID else { return false }
        return dragging != targetBlockID
    }

    func dropEntered(info: DropInfo) {
        edge = nearestEdge(to: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = nearestEdge(to: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        edge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landingEdge = edge ?? nearestEdge(to: info.location)
        defer {
            edge = nil
            tileLayout.draggingBlockID = nil
        }
        guard let dragging = tileLayout.draggingBlockID else { return false }
        tileLayout.move(dragging, to: targetBlockID, edge: landingEdge)
        return true
    }

    private func nearestEdge(to location: CGPoint) -> PaneEdge {
        let bounds = size()
        guard bounds.width > 0, bounds.height > 0 else { return .trailing }
        let dx = location.x / bounds.width - 0.5
        let dy = location.y / bounds.height - 0.5
        if abs(dx) > abs(dy) {
            return dx < 0 ? .leading : .trailing
        } else {
            return dy < 0 ? .top : .bottom
        }
    }
}

/// Hands the window's keyboard focus to the app inside a pane the moment that
/// pane becomes the focused one.
///
/// Why this exists: with the pane header gone, Focus Mode's tab strip is the
/// way to switch panes — and clicking a tab used to only move the host's
/// `focusedBlockID`. The pane came forward looking active (brackets, glow)
/// while the keystrokes still went wherever they went before, so switching to a
/// terminal tab and typing did nothing until you clicked into it. Focus that
/// isn't keyboard focus is a lie the UI tells.
///
/// ## How it finds the app's view — and why not by walking the view tree
///
/// The host can't name the plugin's view; it doesn't know what's inside a pane.
/// The first attempt searched the AppKit hierarchy around a zero-size anchor
/// planted in the pane, and it worked only intermittently. Logging the live
/// tree showed why, and the reason is structural, not a tuning problem:
/// SwiftUI hosts every `NSViewRepresentable` in its own backing layer, so the
/// anchor's subtree never contained the terminal at all — and the depth at
/// which panes became siblings *changed between runs of the same build*.
/// SwiftUI's backing hierarchy is an implementation detail; no amount of
/// climbing or scoping makes it a reliable index.
///
/// So this asks AppKit the question AppKit actually answers: **what visible,
/// interactive view is at this point?** `hitTest` is exactly that, and it
/// already accounts for the thing that makes Focus Mode hard — every pane sits
/// at full canvas size, stacked, and only the focused one is visible and
/// hit-testable (the others are `opacity 0` with hit testing off). So a hit
/// test at the pane's center lands inside the focused pane by construction,
/// with no geometry comparison and no assumptions about tree shape.
private struct PaneKeyFocusAnchor: NSViewRepresentable {
    let isFocused: Bool

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isFocusedPane = isFocused
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        let wasFocused = nsView.isFocusedPane
        nsView.isFocusedPane = isFocused
        // Only on the false → true transition. Claiming the keyboard on every
        // render would fight the user: it would yank focus out of the Launcher
        // field or a tab being renamed on each unrelated redraw.
        guard isFocused, !wasFocused else { return }
        nsView.beginClaimingKeyboard()
    }

    /// A zero-cost marker filling the pane (it is installed as the pane's
    /// background, so its bounds ARE the pane's bounds — that is all the
    /// geometry the hit test needs).
    final class AnchorView: NSView {
        var isFocusedPane = false

        /// Retry schedule, in seconds, walked sequentially and stopping at the
        /// first success.
        ///
        /// The first delay must clear TWO things, and both of them cost
        /// correctness or smoothness when it doesn't:
        ///
        /// 1. **The frame that reveals the pane.** Making a terminal first
        ///    responder costs ~8ms (it redraws) and revealing the pane costs
        ///    ~10ms; in one frame that blows the 16.7ms budget and drops a frame
        ///    on every switch. Measured: 18ms median stall → 1.0ms, against a
        ///    0.9ms idle floor.
        /// 2. **Ambiguity about which pane it is.** This used to have to wait out
        ///    a 170ms content cross-fade, during which BOTH panes were partly
        ///    visible and still hit-testable, so the hit test could land in the
        ///    wrong pane — and the pane at the bottom of the stack, the first
        ///    tab, was the one that systematically lost. That was the "focus
        ///    works on every tab except the first" bug.
        ///
        ///    The cross-fade is gone (it was also what flashed), the focused pane
        ///    now sits on top via `zIndex`, and the claim refuses a target that
        ///    isn't visible. With all three, there is no fade left to wait out,
        ///    so this only has to clear the reveal frame.
        private static let retryDelays: [TimeInterval] = [0.06, 0.12, 0.22, 0.4]

        /// Rising counter so a stale retry chain — from a pane that has since
        /// been unfocused — cannot fire and steal the keyboard back.
        private var claimGeneration = 0
        private var isAwaitingKeyWindow = false

        /// The focused pane should own the keyboard from the moment it appears,
        /// not only after a switch — so claim on mount too.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, isFocusedPane else { return }
            beginClaimingKeyboard()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            stopAwaitingKeyWindow()
        }

        func beginClaimingKeyboard() {
            claimGeneration += 1
            attempt(index: 0, generation: claimGeneration)
        }

        private func attempt(index: Int, generation: Int) {
            guard index < Self.retryDelays.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[index]) { [weak self] in
                guard let self, self.claimGeneration == generation, self.isFocusedPane else { return }
                guard !self.claimKeyboard() else { return }
                self.attempt(index: index + 1, generation: generation)
            }
        }

        /// Returns true once the keyboard is inside this pane, so later retries
        /// become no-ops.
        @discardableResult
        private func claimKeyboard() -> Bool {
            guard let window, let contentView = window.contentView else { return false }
            // At launch the window becomes key only after the panes mount. Wait
            // for it rather than dropping the claim, or the focused pane starts
            // life without the keyboard.
            guard window.isKeyWindow else {
                awaitKeyWindow(window)
                return false
            }
            // Already where we put it last time — the cheap path, and the one
            // every repeat claim takes.
            // A live text field owns the keyboard for a reason (Launcher search,
            // a tab mid-rename, a settings field). Never take it from one.
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return false }
            // The pane must be big enough to aim at — a pane mid-layout at zero
            // size would hit-test into whatever is behind it.
            guard bounds.width > 8, bounds.height > 8 else { return false }

            let centerInContent = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: contentView)
            guard let hit = contentView.hitTest(centerInContent) else { return false }
            // Belt and braces on top of the timing: refuse a view that is not
            // actually on screen. If a cross-fade is still running, or another
            // workspace's pane is somehow the hit, this fails and the next retry
            // tries again rather than handing the keyboard to an invisible
            // terminal — which the user would experience as typing into nothing.
            guard Self.isEffectivelyVisible(hit, upTo: contentView) else { return false }
            guard let target = Self.responderTarget(from: hit) else { return false }
            // Already there — don't disturb exactly where inside the pane.
            if window.firstResponder as? NSView === target { return true }
            return window.makeFirstResponder(target)
        }

        /// The nearest view at or above the hit view that will take the
        /// keyboard. Climbing UP from the hit is safe in a way that climbing
        /// blind was not: the hit view is already known to be inside the
        /// focused pane, and a container that accepts first responder on behalf
        /// of its content (scroll views, representable hosts) is the right
        /// target anyway.
        private static func responderTarget(from hit: NSView) -> NSView? {
            var candidate: NSView? = hit
            while let view = candidate {
                if view.acceptsFirstResponder, view.canBecomeKeyView { return view }
                candidate = view.superview
            }
            return nil
        }

        /// Whether `view` is really visible: nothing between it and `root` is
        /// hidden or faded out. SwiftUI expresses `.opacity()` on a hosted
        /// AppKit view as a layer opacity, so both that and `isHidden` have to
        /// be checked, all the way up.
        private static func isEffectivelyVisible(_ view: NSView, upTo root: NSView) -> Bool {
            var current: NSView? = view
            while let node = current {
                if node.isHidden { return false }
                if node.alphaValue < 0.9 { return false }
                if let opacity = node.layer?.opacity, opacity < 0.9 { return false }
                if node === root { return true }
                current = node.superview
            }
            return true
        }

        /// Re-runs the claim once the window becomes key. Selector-based (not
        /// block-based) observation so it can be torn down from
        /// `viewWillMove(toWindow:)` rather than from a `deinit` that isn't
        /// allowed to touch non-Sendable state.
        private func awaitKeyWindow(_ window: NSWindow) {
            guard !isAwaitingKeyWindow else { return }
            isAwaitingKeyWindow = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }

        private func stopAwaitingKeyWindow() {
            guard isAwaitingKeyWindow else { return }
            isAwaitingKeyWindow = false
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            stopAwaitingKeyWindow()
            guard isFocusedPane else { return }
            beginClaimingKeyboard()
        }
    }
}
