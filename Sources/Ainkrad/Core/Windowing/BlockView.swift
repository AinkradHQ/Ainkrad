import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    // Injected per pane by `WorkspacePaneLayer`.
    @Environment(\.ainkradPaneMode) private var paneMode
    @Environment(\.ainkradSetPaneMode) private var setPaneMode
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
        if isBeingDragged { return skin.opacity.o45 }
        return isFocused ? 1 : skin.opacity.o92
    }

    private var paneScale: CGFloat {
        if !hasArrived && !reduceMotion { return 0.97 }
        return isBeingDragged ? 0.98 : 1
    }

    /// Colours stay on `DesignTokens`, which carry the user's custom accent;
    /// every scalar comes from the skin.
    private var tokens: DesignTokens { environment.themeManager.tokens }

    var body: some View {
        PaneContent(
            app: app, topInset: contentTopInset, fallback: tokens.surface,
            paneLocator: environment.paneLocators.sink(forBlock: block.id),
            launchGeneration: block.launchGeneration
        )
        .overlay(alignment: .top) { grabStrip }
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
        .clipShape(ChamferShape(cut: skin.radius.md))
        // The pane's frame — and, when it becomes the focused one, the pulse of
        // light that now carries the tab transition. Its own view so the pulse
        // animates without re-evaluating this body (and therefore without
        // touching the app's content or the blurred backdrop) on every frame.
        .overlay(PaneActivationRing(isFocused: isFocused))
        .overlay(dropZoneHighlight)
        .shadow(
            color: isFocused
                ? tokens.accentPrimary.opacity(skin.opacity.o28) : skin.color(.palette("black", skin.opacity.o25)),
            radius: isFocused ? skin.size.s22 : skin.size.s12
        )
        .opacity(paneOpacity)
        .scaleEffect(paneScale)
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
        // Clicking a Focus-Mode tab focuses the pane; this hands the KEYBOARD
        // to the app inside it, so the terminal that just came forward is
        // typeable without a second click.
        .background(PaneKeyFocusAnchor(isFocused: isFocused))
        .animation(.easeOut(duration: skin.motion.fast), value: isBeingDragged)
        // When the drag session ends (drop landed elsewhere, or released
        // over no target), drop any lingering preview highlight — SwiftUI
        // doesn't reliably call dropExited on panes the drag merely passed
        // over, so this is the guaranteed clear.
        .onChange(of: tileLayout.draggingBlockID) { _, newValue in
            if newValue == nil { dropEdge = nil }
        }
        .onDrop(
            of: [.text],
            delegate: PaneEdgeDropDelegate(
                targetBlockID: block.id,
                tileLayout: tileLayout,
                size: { paneSize },
                edge: $dropEdge
            )
        )
        .animation(.easeOut(duration: skin.motion.fast), value: isFocused)
        .animation(.easeOut(duration: skin.motion.durations.d0_1), value: dropEdge)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: skin.motion.fast)) { hasArrived = true }
        }
    }

    /// The half of this pane the dragged pane would occupy — a live drop
    /// preview in the targeting language: accent wash, corner brackets,
    /// and a split-direction glyph, animating between edges as the drag
    /// moves.
    @ViewBuilder
    private var dropZoneHighlight: some View {
        // A drop preview only means anything while a drag is in flight —
        // gating on the live drag flag (which every render observes)
        // guarantees the highlight vanishes the instant the drag ends, even
        // if a stale `dropEdge` lingers from a pane the drag passed over.
        if let dropEdge, tileLayout.draggingBlockID != nil {
            let isHorizontal = dropEdge == .leading || dropEdge == .trailing
            let zone = ChamferShape(cut: skin.radius.sm)
                .fill(tokens.accentPrimary.opacity(skin.opacity.o16))
                .overlay(
                    ChamferShape(cut: skin.radius.sm)
                        .strokeBorder(tokens.accentSecondary.opacity(skin.opacity.o65), lineWidth: 1)
                )
                .overlay(
                    TargetingBrackets(length: skin.size.s9)
                        .stroke(tokens.accentSecondary.opacity(skin.opacity.o90), lineWidth: 1.5)
                        .padding(skin.spacing.xs)
                )
                .overlay(
                    Image(systemName: isHorizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                        .font(skin.font(AinkradFontToken(sizeKey: "t15", weight: "medium", scaled: false)))
                        .foregroundStyle(tokens.accentSecondary.opacity(skin.opacity.o85))
                        .shadow(color: tokens.accentSecondary.opacity(skin.opacity.o80), radius: skin.size.s6)
                )
                .padding(skin.size.s3)
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
    private var grabStrip: some View {
        // Built here, while the view is installed, so the preview closure
        // (called at drag start) captures resolved colours and sizes.
        let ghost = dragGhost
        return Color.clear
            .frame(height: max(contentTopInset, skin.size.s10))
            .overlay {
                Capsule()
                    .fill(tokens.foreground.opacity(isHoveringGrabber ? skin.opacity.o35 : 0))
                    .frame(width: skin.size.s34, height: skin.size.s3)
            }
            .contentShape(Rectangle())
            .onHover { isHoveringGrabber = $0 }
            .animation(.easeOut(duration: skin.motion.durations.d0_12), value: isHoveringGrabber)
            .onDrag {
                tileLayout.focus(block.id)
                tileLayout.draggingBlockID = block.id
                return NSItemProvider(object: block.id.uuidString as NSString)
            } preview: {
                ghost
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
        // The way back to basic from advanced. It lives here, in the host,
        // rather than in nine advanced roots: the pane is chromeless and this
        // menu is its only host-owned control surface.
        if app?.supportsModes == true {
            let isBasic = paneMode == .basic
            items.append(
                AinkradMenuItem(
                    title: isBasic ? "Show Everything" : "Simplify",
                    systemName: isBasic
                        ? "arrow.down.left.and.arrow.up.right"
                        : "arrow.up.right.and.arrow.down.left"
                ) {
                    setPaneMode(isBasic ? .advanced : .basic)
                })
        }
        if let workspace {
            items.append(
                AinkradMenuItem(
                    title: isInFocusMode ? "Back to Split Mode" : "Focus Mode",
                    systemName: isInFocusMode ? "rectangle.split.2x2" : "rectangle.inset.filled"
                ) {
                    tileLayout.focus(block.id)
                    workspace.viewMode = isInFocusMode ? .split : .focus
                    environment.sounds.play(.focusMode)
                })
        }
        items.append(
            AinkradMenuItem(title: "Reset Layout", systemName: "arrow.counterclockwise") {
                tileLayout.resetLayout()
            })
        items.append(
            AinkradMenuItem(title: "Close", systemName: "xmark", isDestructive: true) {
                environment.sounds.play(.appClose)
                tileLayout.close(block.id)
            })
        return items
    }

    /// Termius-style drag ghost: a small pill, not the whole pane — the app's
    /// neon tile at HUD size (matching the Launcher rows) and the pane's name.
    private var dragGhost: some View {
        HStack(spacing: skin.size.s6) {
            NeonAppTile(symbol: app?.icon ?? "app", tokens: tokens, size: skin.size.s18)
            Text(block.displayTitle(appName: app?.displayName))
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(tokens.foreground)
        }
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s5)
        .background(tokens.surfaceElevated)
        .clipShape(Capsule())
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
        app?.chromeFill() == nil ? 0 : skin.spacing.md
    }
}
