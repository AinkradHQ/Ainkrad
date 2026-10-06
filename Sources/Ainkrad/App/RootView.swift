import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The single window's content: every workspace's tile layout stays
/// mounted (hidden when inactive) so running sessions survive switching;
/// the Launcher and Workspace Overview overlay on top when summoned.
struct RootView: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.ainkradReduceMotion) var reduceMotion

    private var isOverlayPresented: Bool {
        var presented =
            environment.isSetupPresented || environment.isLauncherPresented || environment.isWorkspaceOverviewPresented
            || environment.isSettingsPresented
            || environment.isAppStorePresented || environment.isQuickAskPresented
            || environment.quitCoordinator.isConfirming
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

            pluginOverlay

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
        .background(
            KeyboardShortcutMonitor(environment: environment, pushToTalkController: environment.voiceService.pushToTalk)
        )
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
}
