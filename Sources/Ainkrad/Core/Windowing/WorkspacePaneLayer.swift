import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// EVERY open pane in EVERY workspace, rendered exactly once, in one flat
/// `ForEach` keyed by stable `Block` id.
///
/// ## Why this spans workspaces
///
/// Panes used to be rendered per workspace, each workspace's `TileLayoutView`
/// owning its own `ForEach`. SwiftUI identity is scoped to a container, so a
/// pane moved between workspaces was a removal from one `ForEach` and an
/// insertion into another — a *new* view, however carefully the `Block` object
/// itself was preserved. For a pane hosting an AppKit view that meant
/// `dismantleNSView`, and for Terminal that kills the shell: moving a pane
/// between workspaces destroyed the session, verified by watching the shell PID
/// change (17706 killed, 19328 spawned) across a single move.
///
/// `TileLayoutView` already stated the principle — "every panel renders exactly
/// once, in a flat layer keyed by its stable Block id; the layout tree only
/// computes frames, so structural changes MOVE views instead of re-creating
/// them" — it just stopped at the workspace boundary. This carries it across.
/// One `ForEach` over every pane in the app means a cross-workspace move is a
/// change of position and nothing else: SwiftUI moves the view, the AppKit view
/// is never dismantled, and the shell keeps running.
///
/// Each pane is placed by composing two offsets: where its workspace sits in the
/// carousel, and where the pane sits inside that workspace's canvas.
struct WorkspacePaneLayer: View {
    @Environment(AppEnvironment.self) private var environment
    let registry: BuiltInAppRegistry
    /// The carousel's full size — one workspace's worth.
    let size: CGSize
    /// One-shot zoom applied to the visible panes on a Focus-Mode toggle.
    let focusPop: CGFloat

    private var manager: WorkspaceManager { environment.workspaceManager }

    /// This pane's effective mode: what the user switched it to, else the app's
    /// resolved default. `nil` on the block means "keep following the setting",
    /// so changing the setting moves every pane that was never switched.
    private func mode(for placement: PanePlacement) -> PluginMode {
        if let switched = placement.block.mode { return switched }
        guard let app = registry.allApps.first(where: { $0.id == placement.block.appID })
        else { return .advanced }
        return environment.appAppearanceStore.effectiveMode(for: app)
    }

    var body: some View {
        let activeIndex = manager.workspaces.firstIndex { $0.id == manager.activeWorkspaceID } ?? 0

        ZStack(alignment: .topLeading) {
            ForEach(placements(activeIndex: activeIndex), id: \.block.id) { placement in
                BlockView(
                    block: placement.block,
                    tileLayout: placement.workspace.tileLayout,
                    registry: registry,
                    workspace: placement.workspace,
                    paneSize: placement.frame.size
                )
                // Focus Mode resizes immediately (no debounce) so the tile→full
                // grow fills without an empty flash; Split Mode keeps the
                // trailing debounce. Keyed on the MODE, not on which pane is
                // focused — see the note in `PaneGeometryResolver`.
                .environment(\.paneResizesImmediately, placement.isInFocusMode)
                // Generation 8: the HOST says which pane is active. Plugins
                // previously had to infer it — Terminal bound the agent's
                // context to whichever pane was created last, so with two
                // terminals open the assistant read the wrong buffer, silently.
                .environment(\.ainkradPaneIsFocused, placement.isFocusedPane)
                // Generation 11: the pane's mode, and the way to change it.
                // Injected HERE, beside focus, for the same reason — it is
                // per-pane state only the host can answer, and `PaneContent`'s
                // inputs are deliberately memoized, so a freshly built closure
                // threaded through it would compare unequal every render.
                .environment(\.ainkradPaneMode, mode(for: placement))
                .environment(\.ainkradSetPaneMode) { [block = placement.block] newMode in
                    block.mode = newMode
                }
                .scaleEffect(placement.isVisible ? focusPop : 1)
                .opacity(placement.isVisible ? 1 : 0)
                // The visible pane sits on top, which is what lets the keyboard
                // claim's hit test resolve the right pane out of a Focus-Mode
                // stack (see `PaneKeyFocusAnchor`).
                .zIndex(placement.isVisible ? 1 : 0)
                .frame(width: max(placement.frame.width, 0), height: max(placement.frame.height, 0))
                .position(x: placement.frame.midX, y: placement.frame.midY)
                .allowsHitTesting(placement.isVisible)
                .accessibilityHidden(!placement.isVisible)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Where every pane in the app goes, and whether it can be seen.
    private func placements(activeIndex: Int) -> [PanePlacement] {
        manager.workspaces.enumerated().flatMap { index, workspace -> [PanePlacement] in
            let carouselOffset = CGFloat(index - activeIndex) * size.width
            let isActiveWorkspace = index == activeIndex
            return PaneGeometryResolver.placements(
                for: workspace,
                in: size,
                carouselOffsetX: carouselOffset,
                isActiveWorkspace: isActiveWorkspace
            )
        }
    }
}

/// One pane's resolved position and state.
struct PanePlacement {
    let workspace: Workspace
    let block: Block
    /// Frame in the carousel's coordinate space — the workspace's carousel
    /// offset already folded in.
    let frame: CGRect
    let isVisible: Bool
    let isFocusedPane: Bool
    let isInFocusMode: Bool
}

/// Resolves pane frames for a workspace. Split out from the views so both the
/// pane layer and the per-workspace chrome (which draws the seams BETWEEN those
/// panes) compute from one implementation, and so the geometry is testable
/// without a view hierarchy.
enum PaneGeometryResolver {

    /// Whether this workspace shows the Focus-Mode tab strip. A lone tab is
    /// chrome that earns nothing, so the strip needs two or more panes.
    static func showsTabStrip(_ workspace: Workspace) -> Bool {
        workspace.viewMode == .focus && workspace.tileLayout.blocks.count > 1
    }

    /// True when the workspace is presenting one pane full-canvas with the rest
    /// behind tabs.
    static func isInFocusMode(_ workspace: Workspace) -> Bool {
        workspace.viewMode == .focus && workspace.tileLayout.blocks.count > 1
    }

    static func placements(
        for workspace: Workspace,
        in size: CGSize,
        carouselOffsetX: CGFloat,
        isActiveWorkspace: Bool
    ) -> [PanePlacement] {
        let layout = workspace.tileLayout
        let canvas = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: showsTabStrip(workspace))
        // Always compute the normal split geometry. Focus Mode is handled here
        // WITHOUT collapsing panes to zero size — zero-resizing a terminal
        // corrupts and duplicates its output.
        let geometry = layout.paneGeometry(in: canvas.size, gap: AinkradSpacing.sm, collapseTo: nil)
        let inFocus = isInFocusMode(workspace)
        let focusedID = layout.focusedBlockID
        let fullRect = CGRect(origin: .zero, size: canvas.size)

        return layout.blocks.map { block in
            let normalFrame = geometry.frames[block.id] ?? .zero
            let isFocusedPane = block.id == focusedID
            // In Focus Mode EVERY pane sits at full-canvas size — only the
            // focused one is shown. Holding them all full (rather than at their
            // split frame) makes switching the active pane a pure visibility
            // swap: no resize, so no reflow lag or flash on switch. Panes resize
            // once on entering or leaving Focus, never on switch.
            let localFrame = inFocus ? fullRect : normalFrame
            let visibleInWorkspace = inFocus
                ? isFocusedPane
                : (normalFrame.width >= 1 && normalFrame.height >= 1)

            return PanePlacement(
                workspace: workspace,
                block: block,
                frame: localFrame.offsetBy(
                    dx: canvas.minX + carouselOffsetX,
                    dy: canvas.minY
                ),
                isVisible: isActiveWorkspace && visibleInWorkspace,
                isFocusedPane: isFocusedPane,
                isInFocusMode: inFocus
            )
        }
    }
}
