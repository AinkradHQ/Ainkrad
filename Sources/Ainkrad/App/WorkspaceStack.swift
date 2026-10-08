import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Everything an overlay sits in front of: the ambient sky, the HUD bar, the
/// deferred-setup banner and the workspace carousel.
///
/// Extracted from `RootView` for one measured reason — see `OverlayBackdrop`.
/// It takes no inputs and reads what it needs from the environment, so SwiftUI
/// has nothing to diff when an overlay flag flips and skips rebuilding the whole
/// live composition.
struct WorkspaceStack: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin

    /// A one-shot zoom for the focused pane on a Focus toggle: it pops from this
    /// scale back to 1. A *scale* (not a frame morph) so the terminal's cols and
    /// rows never change mid-animation — the size still snaps in one step (one
    /// clean reflow) while the pane visually grows into place.
    @State private var focusPop: CGFloat = 1

    /// The home structure the theme's language picks. No `default:` on
    /// purpose: a new layout kind (Metro's `tileGrid`) must not compile until
    /// it is handled here.
    var body: some View {
        switch environment.themeManager.homeLanguage.layout {
        case .islands: islandsHome
        }
    }

    /// The Neon home: the sky (or, for a theme without one, the plain
    /// background) behind the HUD bar and the workspace carousel. The sky is
    /// swapped out rather than hidden, so its `TimelineView` stops entirely;
    /// the stack after it keeps its identity, so panes survive a theme switch.
    private var islandsHome: some View {
        ZStack {
            if environment.themeManager.homeLanguage.sky {
                AmbientSkyView()
            } else if skin.material.kind == "glass" {
                // E3.2: the window is clear under glass, so this one layer
                // shows the desktop behind the whole stack.
                AinkradMaterialBackground(level: .hud, blending: .behindWindow).ignoresSafeArea()
            } else {
                skin.color(\.background).ignoresSafeArea()
            }

            // Extends under the (hidden) title bar so the HUD is the
            // top of the screen itself — the traffic lights float
            // inside it. The bar is always shown; in full screen it also
            // carries the status readouts, and the traffic lights within
            // it reveal on top-edge hover (see `HUDBar`).
            VStack(spacing: 0) {
                HUDBar()

                // Persistent, undismissable: the app genuinely cannot do
                // its main job in this state, and the user chose to postpone
                // fixing it. Hidden while the gate is up so the wizard it
                // summons is not shouted at from behind.
                if environment.deferredSetupSteps.contains(.providers),
                    !environment.isSetupPresented
                {
                    SetupDeferredProvidersBanner()
                }

                // ALL workspaces stay in the hierarchy — switching
                // only toggles visibility, so PTY-backed sessions in
                // background workspaces keep running. They're laid out
                // as a horizontal carousel: the active one sits at
                // center, the others wait one screen-width to either
                // side by their order, so switching slides the new
                // workspace in from the direction it lives (spatially
                // matching the HUD's workspace row).
                workspaceCarousel
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var workspaceCarousel: some View {
        GeometryReader { proxy in
            let manager = environment.workspaceManager
            let activeIndex = manager.workspaces.firstIndex { $0.id == manager.activeWorkspaceID } ?? 0

            ZStack(alignment: .topLeading) {
                // Per-workspace chrome: tab strip, seams, backdrop, badge,
                // empty state. Still one view per workspace, because all of
                // that belongs to one workspace's layout tree.
                ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    let isActive = index == activeIndex
                    TileLayoutView(workspace: workspace, registry: environment.registry)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(isActive ? 1 : 0)
                        .offset(x: CGFloat(index - activeIndex) * proxy.size.width)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                }

                // ONE layer for every pane in every workspace — see
                // `WorkspacePaneLayer`. This is what makes moving a pane
                // between workspaces a reposition rather than a destroy-and-
                // recreate, so a terminal keeps its shell. It sits above the
                // chrome so panes cover the translucency backdrop, and the
                // badge (drawn in the chrome) is deliberately the one piece
                // that does not need to be above them.
                WorkspacePaneLayer(
                    registry: environment.registry,
                    size: proxy.size,
                    focusPop: focusPop
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .animation(skin.motion.springs["sp42_88"].map { skin.animation($0) }, value: manager.activeWorkspaceID)
            // The Focus-Mode zoom, owned here now that the panes are. Only the
            // active workspace's panes are visible, so its mode is the only one
            // that can call for a pop.
            .onChange(of: manager.activeWorkspace.viewMode) { _, _ in
                popFocusedPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Zooms the now-visible pane(s) in on a Focus toggle: set the start scale,
    /// then spring it to 1 on the next tick (so the start frame renders first),
    /// animating only the scale — the pane size has already snapped, so the
    /// terminal never reflows mid-animation.
    private func popFocusedPane() {
        guard !reduceMotion else { return }
        focusPop = 0.92
        // `DispatchQueue.main.async` on purpose (S-CON-5): the spring must
        // start on the next run-loop turn, after the 0.92 frame has rendered.
        DispatchQueue.main.async {
            withAnimation(skin.motion.springs["sp34_80"].map { skin.animation($0) }) {
                focusPop = 1
            }
        }
    }
}
