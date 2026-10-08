import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

private struct PaneResizesImmediatelyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by the layout on the pane that fills the Focus-Mode canvas, so
    /// that pane's content can resize immediately (no debounce) instead of
    /// waiting for the trailing-debounce every other pane uses. App-agnostic:
    /// any pane's content may read this, not just Terminal's.
    var paneResizesImmediately: Bool {
        get { self[PaneResizesImmediatelyKey.self] }
        set { self[PaneResizesImmediatelyKey.self] = newValue }
    }
}

/// One workspace's CHROME: the Focus-Mode tab strip along the top edge, the
/// seams between panes, the translucency backdrop, the shortcut badge, and the
/// island empty state. Everything except the panes.
///
/// RENDERING CONTRACT: every panel renders exactly once, in a flat layer keyed
/// by its stable Block id; the layout tree only computes frames (see
/// `paneGeometry`). Structural changes therefore MOVE views instead of
/// re-creating them — a dragged terminal keeps its live session.
///
/// That flat layer is `WorkspacePaneLayer`, and it lives ABOVE the carousel,
/// spanning every workspace, which is why the panes are not drawn here. Inside
/// one workspace this view used to satisfy the contract on its own; across
/// workspaces it could not, because SwiftUI identity is scoped to a container —
/// so moving a pane to another workspace destroyed and re-created it, killing
/// live sessions. The chrome stays per workspace; the panes went up a level.
///
/// The two lay out against the same rectangle, and both derive it from
/// `PaneCanvasMetrics` so the seams stay between the panes they separate.
struct TileLayoutView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let workspace: Workspace
    let registry: BuiltInAppRegistry

    /// The pane the floating shortcut badge is currently announcing, and the
    /// pending dismissal a later switch cancels (so switching twice quickly
    /// shows the second badge for its full time rather than having the first
    /// one's timer close it early).
    @State private var badgeBlockID: UUID?
    @State private var badgeDismissal: Task<Void, Never>?

    private var tileLayout: TileLayout { workspace.tileLayout }

    /// True when any pane declares a translucent window fill (via its
    /// `RegisteredApp.chromeFill` alpha) — then the shared blurred backdrop is
    /// rendered behind the panes. App-agnostic: no per-app settings read.
    private var hasTranslucentPane: Bool {
        tileLayout.blocks.contains { block in
            guard let app = registry.allApps.first(where: { $0.id == block.appID }),
                let fill = app.chromeFill()
            else { return false }
            return NSColor(fill).alphaComponent < 1
        }
    }

    var body: some View {
        if tileLayout.isEmpty {
            EmptyWorkspaceView(isActiveWorkspace: workspace.id == environment.workspaceManager.activeWorkspaceID)
        } else {
            GeometryReader { proxy in
                let showsStrip = PaneGeometryResolver.showsTabStrip(workspace)
                let canvas = PaneCanvasMetrics.canvasRect(in: proxy.size, showsTabStrip: showsStrip)
                let stripRect = PaneCanvasMetrics.tabStripRect(in: proxy.size)

                ZStack(alignment: .topLeading) {
                    // Everything that lives INSIDE the pane canvas, in
                    // canvas-local coordinates. It is its own container, sized
                    // and offset to the canvas rect, because `"pane-canvas"` is
                    // the coordinate space `SeamView`'s drag gesture resolves
                    // boundary positions in — and those come from
                    // `paneGeometry`, which is canvas-local. Naming the
                    // workspace frame instead would offset every seam drag by
                    // the insets.
                    ZStack(alignment: .topLeading) {
                        // One shared workspace backdrop behind every pane, so
                        // translucent terminals reveal slices of a SINGLE
                        // blurred island rather than each carrying its own.
                        // Only present when transparency is enabled (otherwise
                        // opaque panes cover it).
                        if hasTranslucentPane {
                            workspaceBackdrop
                                .frame(width: canvas.width, height: canvas.height)
                        }

                        seams(in: canvas.size)

                        // Bottom-trailing: out of the way of a terminal's
                        // prompt and of the tab strip it refers to, and the
                        // corner the eye is least likely to be reading when the
                        // pane changes.
                        shortcutBadge
                            .frame(width: canvas.width, height: canvas.height, alignment: .bottomTrailing)
                    }
                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                    .coordinateSpace(name: "pane-canvas")
                    .offset(x: canvas.minX, y: canvas.minY)

                    if showsStrip {
                        FocusTabStrip(workspace: workspace)
                            .frame(width: stripRect.width, height: stripRect.height)
                            .offset(x: stripRect.minX, y: stripRect.minY)
                            // Only the strip fades in/out; the panes must NOT
                            // animate their size on a Focus toggle (that flood
                            // of intermediate resizes duplicates terminal
                            // output).
                            .transition(.opacity)
                            .animation(.easeInOut(duration: skin.motion.durations.d0_2), value: workspace.viewMode)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .onChange(of: tileLayout.focusedBlockID) { _, newValue in
                    guard workspace.viewMode == .focus, tileLayout.blocks.count > 1 else { return }
                    announceShortcut(for: newValue)
                }
            }
        }
    }

    /// The energy seams between sibling panes. Drawn here rather than in the
    /// pane layer because they belong to ONE workspace's split tree, and
    /// positioned from the same `PaneCanvasMetrics` rectangle the panes use so
    /// they land exactly in the gaps between them.
    @ViewBuilder
    private func seams(in canvasSize: CGSize) -> some View {
        if !PaneGeometryResolver.isInFocusMode(workspace) {
            let geometry = tileLayout.paneGeometry(in: canvasSize, gap: AinkradSpacing.sm, collapseTo: nil)
            ForEach(geometry.seams) { seam in
                SeamView(placement: seam, tileLayout: tileLayout)
                    .frame(width: seam.frame.width, height: seam.frame.height)
                    .offset(x: seam.frame.minX, y: seam.frame.minY)
            }
        }
    }

    // MARK: - Shortcut badge

    /// Shows the badge for the pane that just came forward, then dismisses it.
    /// Each announcement cancels the previous one's dismissal: only the most
    /// recent announcement is allowed to clear the state.
    private func announceShortcut(for blockID: UUID?) {
        guard let blockID else { return }
        badgeDismissal?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_14)) {
            badgeBlockID = blockID
        }
        badgeDismissal = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: skin.motion.durations.d0_22)) {
                badgeBlockID = nil
            }
        }
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        if let badgeBlockID,
            let index = tileLayout.blocks.firstIndex(where: { $0.id == badgeBlockID })
        {
            let block = tileLayout.blocks[index]
            let appName = registry.allApps.first { $0.id == block.appID }?.displayName
            PaneShortcutBadge(
                title: block.displayTitle(appName: appName),
                shortcut: PaneShortcut.label(forOrdinal: index)
            )
            .padding(skin.spacing.md)
            .transition(.opacity)
        }
    }

    /// The backdrop revealed through any translucent pane. It deliberately does
    /// NOT paint an opaque base: the global `AmbientSkyView` (sky + live motion)
    /// is already mounted behind the whole carousel, so leaving this layer
    /// transparent lets that living scene show through. In front of the sky it
    /// renders the real `FloatingIslandView` — framed exactly like the empty
    /// workspace — so a translucent pane reveals the SAME island a user sees on
    /// an empty workspace, not a static blurred stand-in. A single faint scrim
    /// keeps pane content legible over a busy sky. A theme without the island
    /// art (`islandArt: false`) keeps only the scrim.
    private var workspaceBackdrop: some View {
        let tokens = environment.themeManager.hostSkin
        return ZStack {
            // Match the empty workspace's island placement. There the island is
            // the top child of a centered stack that also holds the shortcut
            // hints below it, so the island sits ABOVE the geometric center.
            // Centering the island alone would drop it lower, making it appear
            // to "slide down" when a pane opens — so reserve the same hint
            // footprint (~two hint rows + their top padding) beneath it, keeping
            // the revealed island at the exact height it has on the main screen.
            if environment.themeManager.homeLanguage.islandArt {
                VStack(spacing: 0) {
                    FloatingIslandView()
                        .frame(maxWidth: skin.size.s860, maxHeight: skin.size.s574)
                    Color.clear.frame(height: skin.size.s72)
                }
            }
            // Legibility scrim only — low enough that motion clearly shows
            // through, high enough that text over a busy sky stays readable.
            // Tuned during screenshot review.
            tokens.color(\.background).opacity(skin.opacity.o12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// An energy seam between sibling panes, absolutely positioned by its
/// `SeamPlacement`: a thin accent gradient line in the gap, with a grabber
/// capsule that brightens on hover and while dragging to resize.
private struct SeamView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    let placement: SeamPlacement
    let tileLayout: TileLayout

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        let tokens = environment.themeManager.hostSkin
        let isLit = isHovering || isDragging
        let seamAlpha = isLit ? skin.opacity.o90 : skin.opacity.o22
        let seamWidth = isLit ? skin.size.s2 : skin.size.s1

        Group {
            if placement.axis == .horizontal {
                LinearGradient(
                    colors: [.clear, tokens.color(\.accentSecondary).opacity(seamAlpha), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: seamWidth)
                .frame(maxWidth: .infinity)
                .overlay {
                    if isLit {
                        Capsule()
                            .fill(tokens.color(\.accentSecondary))
                            .frame(width: skin.size.s3, height: skin.size.s22)
                            .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o90), radius: skin.size.s4)
                    }
                }
            } else {
                LinearGradient(
                    colors: [.clear, tokens.color(\.accentSecondary).opacity(seamAlpha), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: seamWidth)
                .frame(maxHeight: .infinity)
                .overlay {
                    if isLit {
                        Capsule()
                            .fill(tokens.color(\.accentSecondary))
                            .frame(width: skin.size.s22, height: skin.size.s3)
                            .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o90), radius: skin.size.s4)
                    }
                }
            }
        }
        .shadow(color: isLit ? tokens.color(\.accentSecondary).opacity(skin.opacity.o70) : .clear, radius: skin.size.s5)
        // Grab target is wider than the 1px seam so the boundary is easy to
        // catch with the mouse without hunting for a hairline.
        .contentShape(Rectangle().inset(by: -skin.size.s6))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("pane-canvas"))
                .onChanged { value in
                    isDragging = true
                    let location = placement.axis == .horizontal ? value.location.x : value.location.y
                    let position = (location - placement.containerOrigin) / max(placement.containerLength, 1)
                    tileLayout.setBoundary(path: placement.path, after: placement.index, to: position)
                }
                .onEnded { _ in
                    isDragging = false
                    tileLayout.onStructuralChange?()
                }
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                (placement.axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: skin.motion.durations.d0_12), value: isLit)
    }
}
