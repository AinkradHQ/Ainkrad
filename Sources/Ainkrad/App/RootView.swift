import SwiftUI
import AinkradAppKit

/// The single window's content: every workspace's tile layout stays
/// mounted (hidden when inactive) so running sessions survive switching;
/// the Launcher and Workspace Overview overlay on top when summoned.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var isOverlayPresented: Bool {
        var presented = environment.isSetupPresented || environment.isLauncherPresented || environment.isWorkspaceOverviewPresented || environment.isSettingsPresented
            || environment.isAppStorePresented || environment.isQuickAskPresented || environment.quitCoordinator.isConfirming
            || environment.presentedOverlayAppID != nil
        #if DEBUG
        presented = presented || environment.isComponentGalleryPresented
        #endif
        return presented
    }

    /// The notification overlays animate on their OWN flags, deliberately not
    /// by joining `isOverlayPresented`.
    ///
    /// That value also drives `OverlayBackdrop(isBlurred:)`, which blurs the
    /// whole workspace behind a summoned overlay. The bell dropdown is
    /// explicitly not a modal (see `SignalBellDropdownOverlay`), so folding it
    /// in there would dim the workspace behind a five-row glance.
    ///
    /// Until this existed, neither notification overlay animated at all: both
    /// carried a `.transition`, but no animation transaction ever ran for the
    /// flags that presented them, so a transition that looked correct in the
    /// diff produced a hard pop on screen.
    private var signalOverlayDepth: Int {
        (environment.isSignalDropdownPresented ? 1 : 0)
            + (environment.isSignalFeedPresented ? 2 : 0)
    }

    /// The app of the focused pane in the active workspace, so Settings can
    /// open directly on that app's section (e.g. Terminal when one is focused).
    private var focusedAppID: String? {
        let layout = environment.workspaceManager.activeWorkspace.tileLayout
        return layout.blocks.first { $0.id == layout.focusedBlockID }?.appID
    }

    var body: some View {
        ZStack {
            // Sky and workspace blur TOGETHER while an overlay is up —
            // blurring only the workspace would rasterize it separately
            // from the sky and visibly seam the composition.
            //
            // `WorkspaceStack` is its own view, taking no inputs, so raising an
            // overlay does NOT rebuild it. Inline here it was rebuilt whenever
            // this body re-evaluated — and this body re-evaluates on every
            // overlay flag — so summoning the Workspace Overview reconstructed
            // the live sky, the HUD bar and every mounted workspace in the same
            // frame that rasterized the blur.
            OverlayBackdrop(isBlurred: isOverlayPresented) {
                WorkspaceStack()
            }

            // Every overlay fades, and none of them scale.
            //
            // They all used to arrive with `.scale(scale: 0.985)` as well — a
            // 1.5% size change, which is close to invisible, over a panel whose
            // shared chrome hosts an `NSVisualEffectView` doing within-window
            // blur. Scaling that forces AppKit to re-blur on every frame of the
            // transition, and it measured at ~12ms of main-thread time per open
            // against a 0.9ms idle floor. An imperceptible flourish is not worth
            // a dropped frame, so the transition is the fade alone.
            if environment.isLauncherPresented {
                LauncherView(store: environment.launcherStore) {
                    environment.isLauncherPresented = false
                }
                .transition(.opacity)
            }

            if environment.isWorkspaceOverviewPresented {
                WorkspaceOverviewView {
                    environment.isWorkspaceOverviewPresented = false
                }
                .transition(.opacity)
            }

            if environment.isSettingsPresented {
                SettingsOverlayView(focusedAppID: focusedAppID) {
                    environment.isSettingsPresented = false
                }
                .transition(.opacity)
            }

            if environment.isAppStorePresented {
                AppStoreOverlayView(store: environment.appStoreStore) {
                    environment.isAppStorePresented = false
                }
                .transition(.opacity)
            }

            signalOverlays

            if environment.isQuickAskPresented {
                QuickAskOverlayView {
                    environment.isQuickAskPresented = false
                }
                .transition(.opacity)
            }

            #if DEBUG
            if environment.isComponentGalleryPresented {
                ComponentGalleryView {
                    environment.isComponentGalleryPresented = false
                }
                .transition(.opacity)
            }
            #endif

            if environment.quitCoordinator.isConfirming {
                QuitConfirmationView()
                    .transition(.opacity)
                    // Above everything, including the first-run gate: ⌘Q must
                    // still quit while setup is up, and a confirmation HUD the
                    // gate covered would be exactly the trap the gate must not be.
                    .zIndex(200)
            }

            if let id = environment.presentedOverlayAppID,
               let app = environment.registry.allApps.first(where: { $0.id == id }) {
                PluginOverlayView(app: app, tokens: environment.themeManager.tokens) {
                    environment.presentedOverlayAppID = nil
                }
                .transition(.opacity)
            }

            // Toasts. Above the workspace and every dismissible overlay, but
            // deliberately BELOW the first-run gate (zIndex 100) and the quit
            // confirmation (200): a toast is not interactive enough to matter,
            // and one floating over the gate would be another surface the
            // scrim cannot cover.
            signalToasts

            // The first-run gate. Deliberately no `onDismiss` closure, no scrim
            // tap and no escape handler — that trio is exactly what makes every
            // overlay above dismissible, and this one must not be. It sits last
            // in the ZStack and carries the highest zIndex so it is above every
            // other overlay, always, whatever order they were raised in.
            if environment.isSetupPresented {
                SetupOverlayView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isOverlayPresented)
        .animation(reduceMotion ? nil : AinkradMotion.present, value: signalOverlayDepth)
        .background(KeyboardShortcutMonitor(environment: environment, pushToTalkController: environment.voiceService.pushToTalk))
        // Each HUD overlay plays `.overlayOpen`/`.overlayClose` as it's
        // summoned/dismissed (AIN-108) — centralized here rather than in each
        // overlay view, since presentation is already driven by these four
        // flags on `environment`. Distinct from `.appLaunch`/`.appQuit`,
        // which are reserved for the Ainkrad app itself starting/quitting.
        .onChange(of: environment.isLauncherPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isSettingsPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isAppStorePresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isWorkspaceOverviewPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isQuickAskPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        #if DEBUG
        .onChange(of: environment.isComponentGalleryPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        #endif
        // Switching the active workspace (⌘1-9, ⌥Tab, cycle, HUD dots all
        // funnel through this one property) plays `.workspaceSwitch`.
        // `onChange` without `initial: true` never fires for the value the
        // view first appears with, so this doesn't fire on launch.
        .onChange(of: environment.workspaceManager.activeWorkspaceID) { _, _ in
            environment.sounds.play(.workspaceSwitch)
        }
    }

    /// The feed's overlays: the bell dropdown and the full feed.
    ///
    /// Extracted from the main `ZStack` because that body outgrew the type
    /// checker once these were added — SwiftUI's inference cost is
    /// superlinear in a single builder, so a large ZStack must be split rather
    /// than grown.
    @ViewBuilder
    private var signalOverlays: some View {
        if environment.isSignalDropdownPresented, let center = environment.signalCenter {
            // Anchored below the top bar on the trailing edge, under the bell
            // that opened it. Presented here rather than as an overlay on
            // `HUDBar`, because that strip is 30pt tall and would clip it.
            SignalBellDropdownOverlay(center: center, hub: environment.signalEmitterHub) {
                environment.isSignalDropdownPresented = false
            } onViewAll: {
                environment.isSignalDropdownPresented = false
                environment.isSignalFeedPresented = true
            }
            .zIndex(60)
        }

        // The consent prompt. Raised as a HUD overlay rather than inline in the
        // App Store's install flow, because an install is not the only way an
        // app arrives — `ainkrad dev`, a sideload and a catalog update all end
        // with a declared subscription nobody has answered, and a prompt that
        // only existed in the store flow would silently skip all three.
        //
        // Below the first-run gate and the quit confirmation, like every other
        // dismissible overlay: a permission prompt floating over the gate
        // would be the one surface the scrim cannot cover.
        if let appID = environment.pendingSubscriptionApprovals.first,
           let subscriptions = environment.signalSubscriptions,
           let app = environment.registry.allApps.first(where: { $0.id == appID }) {
            SubscriptionApprovalView(
                appName: app.displayName,
                subscriptions: subscriptions.declared(for: appID),
                displayName: { id in
                    environment.registry.allApps.first { $0.id == id }?.displayName ?? id
                },
                // True when this app was approved before and has widened its
                // list. `isApproved` is false either way, so the flag comes
                // from whether anything was ever approved for it.
                isReapproval: subscriptions.hasEverBeenApproved(appID: appID),
                onAllow: {
                    subscriptions.approve(appID: appID)
                    if let factory = app.signalObserverFactory {
                        subscriptions.register(observer: factory(), appID: appID)
                    }
                    environment.pendingSubscriptionApprovals.removeFirst()
                },
                onDeny: {
                    // Nothing is recorded as denied: the app simply stays
                    // unapproved, which is the same state it was in before
                    // asking. Storing a "denied" verdict would mean deciding
                    // when to ask again, and the honest answer — when the app
                    // changes what it wants — is exactly what an absent
                    // approval already expresses.
                    subscriptions.revoke(appID: appID)
                    environment.pendingSubscriptionApprovals.removeFirst()
                })
                .transition(.opacity)
                .zIndex(70)
        }

        if environment.isSignalFeedPresented, let center = environment.signalCenter {
            SignalFeedOverlayView(
                center: center,
                hub: environment.signalEmitterHub,
                onDismiss: { environment.isSignalFeedPresented = false },
                viewStateStore: environment.signalViewStateStore,
                // The rail's "Notification settings…" lands in Settings, on the
                // Notifications page, rather than opening a second control
                // surface that would then disagree with the first.
                onConfigureSource: { _ in
                    environment.isSignalFeedPresented = false
                    environment.isSettingsPresented = true
                })
            // Scale from just under, like every other summoned HUD panel,
            // rather than the bare cross-fade it had: a fade alone reads as a
            // web modal, and the feed is the largest surface in the family.
            .transition(reduceMotion
                        ? .opacity
                        : .scale(scale: 0.97).combined(with: .opacity))
        }
    }

    /// Transient toasts, top-trailing under the bell that counts them.
    ///
    /// Above the workspace and every dismissible overlay, but deliberately
    /// BELOW the first-run gate (zIndex 100) and the quit confirmation (200): a
    /// toast floating over the gate would be another surface the scrim cannot
    /// cover.
    private var signalToasts: some View {
        SignalToastStack(
            model: environment.signalToasts,
            now: Date(),
            onActivate: { event in
                guard let center = environment.signalCenter else { return }
                // Go to the source, not to the feed. A toast names one specific
                // thing; sending the user to a list of everything makes them
                // find it again. Only an event with nowhere to go falls back.
                center.activate(event)
                if !event.hasDestination { environment.isSignalFeedPresented = true }
                // Acted on, so it goes: a toast still sitting there after it
                // took you somewhere reads as though the tap did nothing.
                environment.signalToasts.dismiss(id: event.id)
            },
            onAction: { event, action in
                let hub = environment.signalEmitterHub
                if action.isDestructive {
                    // A destructive action never fires straight off a toast:
                    // the user clicked something that appeared over their work,
                    // not a confirmation. The feed owns the dialog.
                    environment.signalToasts.dismiss(id: event.id)
                    environment.isSignalFeedPresented = true
                    return
                }
                SignalActionRouter(hub: hub).dispatch(event, action)
                environment.signalToasts.dismiss(id: event.id)
            })
        // Clear of the 30pt top bar, so a toast never covers the clock or the
        // bell whose count it corresponds to.
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(!environment.isSetupPresented)
        .zIndex(50)
    }
}

/// Everything an overlay sits in front of: the ambient sky, the HUD bar, the
/// deferred-setup banner and the workspace carousel.
///
/// Extracted from `RootView` for one measured reason — see `OverlayBackdrop`.
/// It takes no inputs and reads what it needs from the environment, so SwiftUI
/// has nothing to diff when an overlay flag flips and skips rebuilding the whole
/// live composition.
private struct WorkspaceStack: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    /// A one-shot zoom for the focused pane on a Focus toggle: it pops from this
    /// scale back to 1. A *scale* (not a frame morph) so the terminal's cols and
    /// rows never change mid-animation — the size still snaps in one step (one
    /// clean reflow) while the pane visually grows into place.
    @State private var focusPop: CGFloat = 1

    var body: some View {
        ZStack {
            AmbientSkyView()

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
                   !environment.isSetupPresented {
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
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: manager.activeWorkspaceID)
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
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                focusPop = 1
            }
        }
    }
}

/// Blurs everything behind an overlay — the sky, the HUD bar and every mounted
/// workspace — and animates that blur in ONE direction only.
///
/// A SwiftUI `.blur` over the whole window has to rasterize the entire live
/// composition (animated sky, live terminals, every mounted workspace) and
/// Gaussian-blur it. That is the expensive part of raising an overlay, and the
/// two directions are not symmetric, which is the whole point of this type:
///
/// - **Blurring in** is expensive at full radius. Animating it ramps 0 → 14, so
///   the early frames blur at small (cheap) radii and the cost is spread across
///   the transition. Snapping straight to 14 does less total work but pays it
///   all in ONE frame, and one big stall is what a user sees as a glitch.
///   Measured A/B in a single build, back to back: animated 22.1ms median /
///   48.5ms p90, snapped 32.0 / 74.6. Animating wins.
/// - **Blurring out** has nothing to compute at radius 0. Animating it walks
///   back down through every expensive intermediate radius for no visual gain
///   whatsoever — the overlay on top is already fading away. Snapping: 10.8ms
///   median / 22.1ms p90 → 3.5 / 11.6.
///
/// So: ease in, snap out. Both numbers are against a 0.9ms idle floor.
private struct OverlayBackdrop<Content: View>: View {
    /// The radius, tuned so overlay text reads cleanly over a busy sky.
    private static var radius: CGFloat { 14 }

    let isBlurred: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .blur(radius: isBlurred ? Self.radius : 0)
            // `RootView` wraps this whole stack in an `.easeOut(0.16)` keyed on
            // the same flag; this overrides it per direction, and the `nil` on
            // the way out is what stops the blur inheriting it.
            .animation(isBlurred ? .easeOut(duration: 0.16) : nil, value: isBlurred)
    }
}
