import SwiftUI
import UserNotifications
import os
import AinkradAppKit
import AinkradHostRuntime

// Named `AinkradHostApp` (not `AinkradApp`) so the identifier doesn't collide
// with `AinkradAppKit.AinkradApp` — the SDK protocol plugin bundles conform
// to (`PluginLoader.swift`). A same-module type always shadows an imported
// one of the same name, so the SDK protocol would otherwise be unreachable.
@main
struct AinkradHostApp: App {
    // Otherwise-pure-SwiftUI app; this adaptor exists solely so ⌘Q / the app
    // menu's Quit / the Dock's Quit route through `AinkradAppDelegate` →
    // `QuitCoordinator` for the in-app confirmation, instead of terminating
    // immediately.
    @NSApplicationDelegateAdaptor(AinkradAppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment

    init() {
        // FIRST statement in the process's own code: everything below this line,
        // including Home resolution and its `exit(0)` recovery path, is then
        // covered by the handler.
        CrashSentinel.install()
        LaunchSignpost.begin()
        FontRegistrar.registerBundledFonts()
        let home: Home
        // First run: no pointer, so nothing to resolve. The app does NOT ask for a
        // folder here any more — it boots against a provisional Home so the whole
        // environment loads, and raises the setup gate over it. The wizard's Choose
        // Home step adopts the user's real vault and swaps the environment
        // in-session. Nothing is adopted, no pointer is written, and nothing the
        // user authors may be written while this flag is up.
        var provisional = false
        do {
            if case .unset = AinkradHome.resolve() {
                home = LaunchHomeResolver.provisionalHome()
                provisional = true
            } else if LaunchHomeResolver.isRunningTests {
                // The test bundle is hosted by this app, so this initialiser also
                // runs under `xcodebuild test`. Resolving for real there would
                // present a modal folder chooser and hang the suite forever on any
                // machine without a configured Home — and would write a pointer and
                // migrate the developer's real container as a side effect of
                // running tests. A provisional Home keeps the host inert;
                // `LaunchHomeResolver` is tested directly, not through this
                // initialiser.
                home = LaunchHomeResolver.provisionalHome()
            } else {
                // `.missing`/`.foreign` keep their native-alert recovery: those are
                // not first run, and the user already has a Home to be reunited
                // with rather than a wizard to walk through.
                home = try LaunchHomeResolver.resolveWithRecovery()
            }
        } catch {
            // Either the user closed the folder chooser, or they chose Quit from a
            // recovery alert. Both are decisions, not crashes, so `exit(0)` and not
            // `fatalError`. Exiting changes nothing on disk — no pointer was
            // written — so the next launch simply asks again. Nothing else can
            // reach here: `resolveWithRecovery` turns every other failure into an
            // alert the user can act on.
            //
            // `exit(0)` from `init` is correct at this point specifically: `NSApp`
            // exists but is not running, so there is no run loop to unwind and
            // `NSApp.terminate` would do nothing.
            exit(0)
        }
        let bootState = AinkradSignposts.begin(AinkradSignposts.launch, "app-environment-init")
        let environment = AppEnvironment.bootstrap(home: home)
        AinkradSignposts.end(AinkradSignposts.launch, "app-environment-init", bootState)
        environment.isProvisionalHome = provisional
        // Re-gate on an incomplete marker: a real Home whose wizard was
        // force-quit part-way, or one completed at an older `setupVersion` that
        // owes newly added steps, raises the gate exactly as a first run does.
        // The coordinator is built against the just-bootstrapped environment's
        // persistence — the vault's `Config/` store — so this reads the marker
        // from the Home the app actually booted against.
        //
        // Skipped under the test host: it boots against a provisional scratch
        // Home with `provisional == false`, which would otherwise put a gate
        // over the hosted test run for no reason.
        if LaunchHomeResolver.isRunningTests {
            environment.isSetupPresented = false
        } else {
            let coordinator = SetupCoordinator(persistence: environment.persistence,
                                               isProvisionalHome: provisional)
            environment.isSetupPresented = SetupGate.raisedAtLaunch(
                provisionalHome: provisional, setupIsComplete: coordinator.isComplete)
            // Carried into the workspace so a deferred step is visible there
            // rather than silently forgotten. The gate above already re-raises
            // for it; this is what makes the state honest once it comes down.
            environment.deferredSetupSteps = coordinator.deferredSteps
        }
        _environment = State(initialValue: environment)
        Self.install(environment, into: appDelegate)
    }

    /// Points every holder that outlives a view body at `environment`.
    ///
    /// This is the ONLY place the app delegate's store references are written,
    /// so the initial boot and the setup wizard's mid-session re-root
    /// (`HomeAdoption.adoptAndRebuild`, whose `install:` closure calls this)
    /// cannot diverge. A holder assigned anywhere else would keep writing to
    /// the home the app booted against — which during setup is a temporary
    /// directory the OS deletes.
    ///
    /// Everything else that outlives a view body lives INSIDE `AppEnvironment`
    /// (`skillWatcher`, `customCommandWatcher`, `fileChangeWatcher`,
    /// `scheduleRunner`, `remoteChannelService`, `mcpServerRegistry`,
    /// `lspServerRegistry`, `menuBarController`) and is rebuilt wholesale by
    /// `bootstrap`. `KeyboardShortcutMonitor.MonitoringView` re-reads its
    /// `environment` through `updateNSView` when the `@State` swaps.
    ///
    /// **Conditions under which a mid-session swap is safe.** The OUTGOING
    /// environment's long-lived members are not stopped here — `AppEnvironment`
    /// has no `shutdown()`. The swap is therefore only safe while the outgoing
    /// home is a provisional scratch home that satisfies all of:
    ///
    /// 1. No enabled `.fileChange`/`.gitChange` schedules — otherwise the
    ///    outgoing `FileChangeWatcher`'s FSEvents streams (which strongly
    ///    capture `triggerDispatcher` → `runManager` → the OLD `persistence`)
    ///    outlive the swap and keep firing against the scratch home.
    /// 2. No enabled remote channel — otherwise the outgoing `WebhookServer`
    ///    keeps its 127.0.0.1 port bound, routing into the old run graph.
    /// 3. No in-flight agent turn or queued run.
    /// 4. **No secret written while the home is provisional.**
    ///    `Home.keychainServiceName` resolves a vault under the temporary
    ///    directory to a hashed throwaway namespace and a real vault to the
    ///    canonical one (see `Home+KeychainService.swift`). An API key entered
    ///    before adoption therefore lands in a namespace the rebuilt
    ///    environment never reads — the user would see it accepted and then
    ///    find it gone, with no error at all. Any wizard step that collects a
    ///    credential MUST come after Choose Home; `Home.isProvisional` is the
    ///    predicate to assert against.
    ///
    /// `ScheduleRunner` is instantiated and `start()`ed unconditionally
    /// (`AppEnvironment+BootstrapSession.swift`), so unlike 1 and 2 it always
    /// exists across a swap. It is nonetheless inert: its `Timer` block is
    /// `[weak self]` and a scratch home has no schedules, so `tick` is a no-op.
    private static func install(_ environment: AppEnvironment, into appDelegate: AinkradAppDelegate) {
        // The status item is the one surface that escapes the setup gate: it
        // lives on `NSStatusBar.system` and its popover is anchored outside the
        // window, so neither the scrim nor the window-local key monitor reaches
        // it. Suppress it for as long as the gate is up. This is wired here, the
        // single place every environment (boot AND swap) passes through, so the
        // two paths cannot diverge. `[weak environment]` because the environment
        // owns the controller, which owns this closure.
        //
        // Lowering the gate does not re-run this, so the two places that lower
        // it — `SetupDoneStepView.finish()` and the `alreadyConfigured` re-seat
        // in `SetupOverlayView` — call `install()` themselves. It is guarded
        // idempotent, so a redundant call is free.
        environment.menuBarController?.isSuppressed = { [weak environment] in
            environment?.isSetupPresented ?? false
        }
        // Retire the outgoing status item first: `NSStatusBar` would otherwise
        // keep showing it, still bound to the previous environment's presence.
        // No-op on the initial boot, where there is no previous controller.
        //
        // Re-installing the incoming one happens HERE rather than being left to
        // the caller. On the initial boot `applicationDidFinishLaunching` does
        // the install, but by swap time that has long since fired — a caller
        // who merely assigned would be left with a torn-down status item and no
        // menu bar, and nothing in the code would say so. Gated on there having
        // BEEN an outgoing controller, so the boot path is untouched and the
        // delegate still owns the first install. (`MenuBarController.install()`
        // is guarded idempotent anyway: `guard statusItem == nil`.)
        //
        // During the wizard's swap this `install()` is a deliberate no-op: the
        // gate is still up, so `isSuppressed` refuses. The menu bar therefore
        // stays absent from launch until setup finishes, rather than reappearing
        // at the swap — which is the point, since the swap happens at step 2 of 8.
        if appDelegate.menuBarController !== environment.menuBarController,
           let outgoing = appDelegate.menuBarController {
            outgoing.teardown()
            environment.menuBarController?.install()
        }
        appDelegate.quitCoordinator = environment.quitCoordinator
        appDelegate.menuBarController = environment.menuBarController
        appDelegate.assistantSessionStore = environment.assistantSessionStore
        appDelegate.signalSocketServer = environment.signalSocketServer
        appDelegate.signalBannerResponder = environment.signalBannerResponder
        // Registered here as well as in `applicationDidFinishLaunching`,
        // because by swap time that has long since fired and a swapped
        // environment would otherwise leave the delegate pointing at the
        // previous center. Assigning the same object twice is free.
        if let responder = environment.signalBannerResponder {
            UNUserNotificationCenter.current().delegate = responder
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                // The setup wizard's ONLY route to a re-root. Constructed here,
                // in the App, because this is the one place that can both write
                // the `@State` the whole view tree reads and reach
                // `appDelegate` — so the swap goes through the same
                // `Self.install(_:into:)` the initial boot uses, instead of the
                // wizard re-pointing holders at its own call site. `@State`'s
                // setter is nonmutating, so assigning from this escaping
                // closure is legal, and it is what re-renders the tree onto the
                // adopted Home.
                .environment(\.setupHomeInstaller, SetupHomeInstaller { rebuilt in
                    environment = rebuilt
                    Self.install(rebuilt, into: appDelegate)
                })
                // Bridges the host's theme/typography into the SDK's env
                // keys so `AinkradAppKit` components (Gallery, and any
                // plugin that opts in) render theme-correctly. Reading
                // `themeManager.currentTheme`/`uiFontFamily`/`uiFontScale`
                // here — all `@Observable` — keeps this live on theme change.
                .environment(\.ainkradTheme, HostThemeTokens(from: environment.themeManager.currentTheme))
                .environment(\.ainkradStatusColors, AinkradStatusColors(
                    success: environment.themeManager.tokens.success,
                    warning: environment.themeManager.tokens.warning,
                    danger: environment.themeManager.tokens.danger
                ))
                .environment(\.ainkradTypography, AinkradTypography(
                    fontFamilyName: environment.themeManager.uiFontFamily.fontName,
                    scale: environment.themeManager.uiFontScale.multiplier
                ))
                // AINKRAD-controlled motion, independent of the macOS Reduce
                // Motion accessibility toggle — see GlobalSettings.uiReduceMotion.
                // Default false = motion on.
                .environment(\.ainkradReduceMotion, environment.generalSettingsStore.uiReduceMotion)
                // Motion budget source, MUST sit directly below the
                // ainkradReduceMotion injection above — it reads that
                // environment value, so applied above it the budget would
                // silently see reduceMotion == false for the process
                // lifetime (see ainkradMotionBudgetSource()'s doc comment).
                .ainkradMotionBudgetSource()
                // Settings -> Appearance -> Overlays, injected once here rather
                // than threaded through every call site. Before this, only the
                // surfaces that opted into `hudPanelChrome` obeyed the slider;
                // anything built on the SDK's `AinkradPanel` -- the whole
                // notification family, and every plugin panel -- was pinned at
                // 0.94 and always blurred, so the controls looked broken to a
                // user who had just moved them.
                .environment(\.ainkradSurfaceOpacity,
                             environment.generalSettingsStore.overlayBackgroundOpacity)
                .environment(\.ainkradSurfaceBlur,
                             environment.generalSettingsStore.overlayBlurEnabled)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        // Without this the window opens at whatever size AppKit picks, which on
        // a large display is the full visible frame — every resize edge flush
        // against a screen boundary. With `.hiddenTitleBar` there is no title
        // bar to drag either, and `isMovableByWindowBackground` is off (it would
        // steal in-app drags), so the window could not be moved OR resized
        // without zooming it first. A deliberate opening size leaves margin on
        // all four edges.
        //
        // This governs the FIRST launch only: macOS restores a window's frame
        // once the user has moved or resized it, and that restored frame
        // correctly wins over this.
        .defaultSize(width: 1280, height: 840)
        .commands {
            // Menu items for discoverability/mouse use. The actual
            // keyboard delivery goes through KeyboardShortcutMonitor's
            // local event monitor, which is reliable regardless of how
            // the app was launched — see its doc comment.
            // Every item here is disabled while the first-run gate is up. They
            // are mouse-reachable even though the keyboard monitor swallows their
            // chords, and they are NOT all harmless: "New Workspace" mutates and
            // PERSISTS into the provisional Home, a write Task 4's swap then
            // silently discards — precisely the loss this design exists to
            // prevent. "Workspaces…" would latch its overlay invisibly beneath
            // the gate and pop it open the moment setup finishes.
            CommandGroup(after: .newItem) {
                let isGated = environment.isSetupPresented

                Button("Open Launcher") {
                    environment.isLauncherPresented = true
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(isGated)

                Button("New Workspace") {
                    environment.workspaceManager.createWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(isGated)

                Button("Workspaces…") {
                    environment.isLauncherPresented = false
                    environment.isWorkspaceOverviewPresented.toggle()
                }
                .keyboardShortcut(.tab, modifiers: .option)
                .disabled(isGated)

                // ⌥⌘N and ⇧⌥⌘N, chosen after auditing every existing binding:
                // ⌘K, ⌘⇧N, ⌥⇥ and ⌘F are all taken. ⌘⇧N in particular is New
                // Workspace, which an earlier draft of the plan wanted for the
                // feed.
                Button("Notifications") {
                    environment.isSignalDropdownPresented.toggle()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(isGated)

                Button("All Notifications…") {
                    environment.isSignalDropdownPresented = false
                    environment.isSignalFeedPresented = true
                }
                .keyboardShortcut("n", modifiers: [.command, .option, .shift])
                .disabled(isGated)
            }
        }
    }
}

/// The setup wizard's handle on `AinkradHostApp.install(_:into:)`.
///
/// A box rather than a bare closure so it can travel through `EnvironmentValues`
/// with a name, and so the wizard cannot reach anything else in the App: the only
/// thing it can do is hand back a rebuilt environment and have the app adopt it.
/// `nil` in any tree the App did not build (previews, tests). The Home step
/// treats that as "adoption is not available here" and returns BEFORE calling
/// `HomeAdoption.adoptAndRebuild` — deliberately, because that call writes the
/// marker, migrates the legacy container and writes the pointer before `install`
/// is reached. Skipping only the re-point would claim a real vault on disk and
/// then keep running on the provisional one.
struct SetupHomeInstaller {
    let install: @MainActor (AppEnvironment) -> Void

    init(_ install: @escaping @MainActor (AppEnvironment) -> Void) {
        self.install = install
    }
}

private struct SetupHomeInstallerKey: EnvironmentKey {
    static let defaultValue: SetupHomeInstaller? = nil
}

extension EnvironmentValues {
    var setupHomeInstaller: SetupHomeInstaller? {
        get { self[SetupHomeInstallerKey.self] }
        set { self[SetupHomeInstallerKey.self] = newValue }
    }
}

/// Holds the open launch interval between `AinkradHostApp.init` and
/// `applicationDidFinishLaunching`, which are two different types.
enum LaunchSignpost {
    nonisolated(unsafe) private static var state: OSSignpostIntervalState?

    static func begin() {
        state = AinkradSignposts.begin(AinkradSignposts.launch, "launch-to-first-frame")
    }

    static func end() {
        guard let state else { return }
        AinkradSignposts.end(AinkradSignposts.launch, "launch-to-first-frame", state)
        Self.state = nil
    }
}
