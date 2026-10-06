import AppKit
import SwiftUI

/// Installs a local `keyDown` monitor for the app-wide shortcuts (⌘K,
/// ⌘1-⌘9, ⌘⇧N, ⌘W) — see ADR-0008 App Launcher & Workspace Switching.
/// A local monitor fires before the event reaches the menu bar's key
/// equivalents, so it is the reliable delivery path regardless of how the
/// running app was launched; a local monitor (not global/CGEventTap) is
/// sufficient since these shortcuts only need to work while Ainkrad is
/// frontmost, and needs no Accessibility/Input Monitoring permission.
struct KeyboardShortcutMonitor: NSViewRepresentable {
    let environment: AppEnvironment
    /// Forward-dependency seam for AIN voice (Slice 8): `AppEnvironment` does
    /// not yet own a `voiceService` (that lands in Task 13). Until then, the
    /// host passes the push-to-talk controller directly so keyDown/keyUp can
    /// drive it; Task 13 will thread this through `environment.voiceService`
    /// instead and this parameter can fold away.
    var pushToTalkController: PushToTalkController? = nil

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.environment = environment
        view.pushToTalkController = pushToTalkController
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.environment = environment
        nsView.pushToTalkController = pushToTalkController
    }

    final class MonitoringView: NSView {
        var environment: AppEnvironment?
        /// See `KeyboardShortcutMonitor.pushToTalkController` — forward-dependency
        /// seam until `AppEnvironment.voiceService` exists (Task 13).
        var pushToTalkController: PushToTalkController?
        private var monitor: Any?
        private var mouseUpMonitor: Any?
        private var keyUpMonitor: Any?
        private var fullScreenEnterObserver: NSObjectProtocol?
        private var fullScreenExitObserver: NSObjectProtocol?
        private var titlebarObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // One-part screen: no title-bar material or separator may
            // tint the top region — the sky runs edge to edge. The window
            // deliberately does NOT move by background drag — it would
            // steal in-app drags (e.g. Workspace Overview card reorder);
            // the top strip still drags the window.
            if let window {
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
                window.isMovableByWindowBackground = false
                // Initial value on attach — the notifications below only
                // fire on a subsequent transition (AIN-109).
                let isFullScreen = window.styleMask.contains(.fullScreen)
                environment?.isFullScreen = isFullScreen
                // In full screen we host our own top bar; hide the whole OS
                // titlebar so hovering the top edge no longer slides it down
                // over our bar (see `observeFullScreen`).
                setTitlebarHidden(isFullScreen)
            }
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let environment = self.environment, self.handle(event, in: environment) else {
                        return event
                    }
                    return nil
                }
                // Pane drags set a transient "dragging" flag; if the drag
                // ends outside any drop target, no delegate fires — clear
                // it on mouse-up so the lifted pane settles back.
                mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                    if let environment = self?.environment {
                        let layout = environment.workspaceManager.activeWorkspace.tileLayout
                        if layout.draggingBlockID != nil {
                            // `DispatchQueue.main.async` on purpose (S-CON-5):
                            // clear on the next run-loop turn, after any drop
                            // delegate handling this same mouse-up has run.
                            DispatchQueue.main.async {
                                layout.draggingBlockID = nil
                            }
                        }
                    }
                    return event
                }
                // Push-to-talk hold mode needs the key-release edge, which a
                // keyDown monitor never sees — match on keyCode + recording
                // state only (keyUp modifier flags are unreliable), and
                // respect the same recorder gate as `handle` (AIN-144).
                keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                    guard let self, let environment = self.environment,
                        !environment.shortcutStore.isRecordingShortcut,
                        let controller = self.pushToTalkController
                    else {
                        return event
                    }
                    let chord = environment.shortcutStore.chord(for: .pushToTalk)
                    if event.keyCode == chord.keyCode, controller.status == .recording {
                        controller.pressEnded()
                    }
                    return event
                }
                observeFullScreen(of: window)
            } else {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
                if let mouseUpMonitor {
                    NSEvent.removeMonitor(mouseUpMonitor)
                    self.mouseUpMonitor = nil
                }
                if let keyUpMonitor {
                    NSEvent.removeMonitor(keyUpMonitor)
                    self.keyUpMonitor = nil
                }
                titlebarObservation?.invalidate()
                titlebarObservation = nil
                removeFullScreenObservers()
            }
        }

        /// Drives `environment.isFullScreen` from the window's full-screen
        /// transitions (AIN-109) — the source `HUDBar` reads to show/hide the
        /// full-screen status bar.
        private func observeFullScreen(of window: NSWindow?) {
            guard fullScreenEnterObserver == nil else { return }
            fullScreenEnterObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.environment?.isFullScreen = true
                    self?.environment?.isTopBarRevealed = false
                    self?.setTitlebarHidden(true)
                }
            }
            fullScreenExitObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.environment?.isFullScreen = false
                    self?.environment?.isTopBarRevealed = false
                    // Restore the native titlebar + traffic lights for
                    // windowed mode.
                    self?.setTitlebarHidden(false)
                }
            }
        }

        /// Hides/shows the whole system titlebar. In full screen this stops it
        /// from sliding into view over our own top bar when the pointer reaches
        /// the top — hiding only the traffic-light buttons left an empty
        /// titlebar still revealing.
        ///
        /// `NSTitlebarContainerView` is two levels above the standard buttons
        /// (…ContainerView → NSTitlebarView → button). Hiding it once isn't
        /// enough: AppKit sets `isHidden = false` to slide it in whenever the
        /// pointer reaches the top. So we KVO-observe `isHidden` and flip it
        /// straight back — synchronously, before the frame draws — which
        /// suppresses it flash-free (a per-frame poll from the mouse monitor
        /// instead fought the animation and flickered).
        private func setTitlebarHidden(_ hidden: Bool) {
            guard let container = window?.standardWindowButton(.closeButton)?.superview?.superview else { return }
            titlebarObservation?.invalidate()
            titlebarObservation = nil
            if hidden {
                container.isHidden = true
                titlebarObservation = container.observe(\.isHidden, options: [.new]) { view, _ in
                    if view.isHidden == false { view.isHidden = true }
                }
            } else {
                container.isHidden = false
            }
        }

        private func removeFullScreenObservers() {
            if let fullScreenEnterObserver {
                NotificationCenter.default.removeObserver(fullScreenEnterObserver)
                self.fullScreenEnterObserver = nil
            }
            if let fullScreenExitObserver {
                NotificationCenter.default.removeObserver(fullScreenExitObserver)
                self.fullScreenExitObserver = nil
            }
        }

        private func handle(_ event: NSEvent, in environment: AppEnvironment) -> Bool {
            let command = event.modifierFlags.contains(.command)
            let isShifted = event.modifierFlags.contains(.shift)
            let isOption = event.modifierFlags.contains(.option)
            // Resolved once, here, and reused for both the gate and the
            // dispatch below — a second lookup could drift from this one.
            let action = environment.shortcutStore.bindings.action(matching: event)

            // First-run setup is a blocking gate: the workspace renders behind
            // it but nothing in it may be reached. Returning `true` consumes the
            // event (see the local monitor above) WITHOUT performing anything.
            // The overlay owns focus, so only the workspace shortcuts are
            // consumed — everything else must reach its text fields.
            // `SetupGate` owns the decision — including the ⌘Q and
            // quit-confirmation exemptions that keep this a gate rather than a
            // trap — as a pure, tested function.
            if SetupGate.swallows(
                isSetupPresented: environment.isSetupPresented,
                isConfirmingQuit: environment.quitCoordinator.isConfirming,
                isRegisteredShortcut: action != nil,
                isWorkspaceChord: WorkspaceChord.matches(
                    keyCode: event.keyCode,
                    characters: event.charactersIgnoringModifiers?.lowercased(),
                    command: command,
                    option: isOption,
                    shift: isShifted
                ),
                command: command,
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode
            ) {
                return true
            }

            // While the Settings recorder is capturing a chord, this monitor
            // must not act on anything — including a chord that happens to
            // match an existing binding — so it can't fire that action's
            // side effect behind the recorder's back (AIN-144). Local-monitor
            // firing order between the two monitors isn't guaranteed, so this
            // gate has to be the first thing checked, before any dispatch.
            if environment.shortcutStore.isRecordingShortcut {
                return false
            }

            // The six named, rebindable shortcuts (AIN-144) are resolved by
            // the user's current bindings, not a hardcoded key check — this
            // also covers the ⌥Tab Workspace Overview toggle, which used to
            // be special-cased here.
            if let action {
                if action == .pushToTalk {
                    // Forward-dependency seam (Task 13 wires the real
                    // `environment.voiceService.pushToTalk`) — see
                    // `pushToTalkController` above.
                    pushToTalkController?.pressStarted()
                    return true
                }
                return perform(action, in: environment)
            }

            // ⌥1-⌥9 jump straight to a Focus-Mode tab. Placed above the
            // `guard command` below because it is the one pane chord with no
            // Command in it.
            if !environment.isSetupPresented, !environment.isLauncherPresented,
                !environment.isWorkspaceOverviewPresented, !environment.isSettingsPresented,
                !environment.isAppStorePresented,
                let index = WorkspaceChord.paneIndex(
                    keyCode: event.keyCode,
                    command: command,
                    option: isOption,
                    shift: isShifted)
            {
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                guard layout.blocks.indices.contains(index) else { return true }
                layout.focusPane(at: index)
                // No `makeFirstResponder(nil)` here, and none on the pane-arrow
                // path below either: the whole point of moving pane focus is
                // that the pane gets the keyboard, and clearing the first
                // responder is the opposite of that. `PaneKeyFocusAnchor` hands
                // it to the arriving pane's app.
                return true
            }

            guard command else { return false }

            // ⌘⌥←/→ cycle to the previous/next workspace (wrapping around),
            // the quick companion to the ⌘1-9 direct jumps.
            if !environment.isSetupPresented,
                !environment.isLauncherPresented,
                !environment.isWorkspaceOverviewPresented,
                !environment.isSettingsPresented,
                !environment.isAppStorePresented,
                let cycle = WorkspaceChord.cycleDirection(
                    keyCode: event.keyCode,
                    command: command, option: isOption)
            {
                switch cycle {
                case .previous: environment.workspaceManager.switchToPreviousWorkspace()
                case .next: environment.workspaceManager.switchToNextWorkspace()
                }
                window?.makeFirstResponder(nil)
                return true
            }

            // ⌘arrows move pane focus; ⌘⇧arrows resize the focused pane —
            // only while no overlay owns the keyboard (and never when ⌥ is
            // held, which is the workspace-cycle chord above).
            if !environment.isSetupPresented, !environment.isLauncherPresented,
                !environment.isWorkspaceOverviewPresented, !environment.isSettingsPresented,
                !environment.isAppStorePresented,
                let direction = WorkspaceChord.paneDirection(
                    keyCode: event.keyCode,
                    command: command, option: isOption)
            {
                let workspace = environment.workspaceManager.activeWorkspace
                let layout = workspace.tileLayout
                if isShifted {
                    layout.resizeFocused(direction)
                } else if workspace.viewMode == .focus {
                    // In Focus Mode the panes are stacked, not laid out — the
                    // only order the user can see is the tab strip's, so arrows
                    // walk THAT. Walking the split tree here is what made
                    // navigation skip tabs: a geometric step out of a nested
                    // container jumps past its siblings.
                    switch direction {
                    case .left, .up: layout.focusAdjacentInOrder(offset: -1)
                    case .right, .down: layout.focusAdjacentInOrder(offset: 1)
                    }
                } else {
                    layout.focusNeighbor(direction)
                }
                return true
            }

            // `charactersIgnoringModifiers` still applies Shift, so a shifted
            // letter arrives uppercase (⌘⇧A → "A"). Lowercase it so the
            // shifted cases below (matched on `isShifted` + a lowercase letter)
            // fire regardless of case.
            guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

            // Toggle Focus Mode / Split Mode for the active workspace.
            if WorkspaceChord.togglesFocusMode(
                characters: characters,
                command: command, shift: isShifted)
            {
                let workspace = environment.workspaceManager.activeWorkspace
                workspace.viewMode = workspace.viewMode == .focus ? WorkspaceViewMode.split : WorkspaceViewMode.focus
                environment.workspaceManager.persist()
                // Same cue the pane header button and context menu play —
                // ⌘M was the one focus-mode entry point without it.
                environment.sounds.play(.focusMode)
                return true
            }

            // Split the focused pane: ⌘D right, ⌘⇧D down.
            if let edge = WorkspaceChord.splitEdge(
                characters: characters,
                command: command, shift: isShifted)
            {
                environment.workspaceManager.activeWorkspace.tileLayout.splitFocused(edge)
                return true
            }

            if let index = WorkspaceChord.workspaceIndex(
                characters: characters,
                command: command, shift: isShifted)
            {
                environment.workspaceManager.switchToWorkspace(at: index)
                window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        /// Runs the side effect for a resolved named shortcut action — the
        /// exact behavior each one had when it was a hardcoded key check,
        /// now triggered via `ShortcutBindings.action(matching:)` instead.
        private func perform(_ action: ShortcutAction, in environment: AppEnvironment) -> Bool {
            switch action {
            case .openLauncher:
                environment.isWorkspaceOverviewPresented = false
                environment.isSettingsPresented = false
                environment.isAppStorePresented = false
                environment.isQuickAskPresented = false
                if environment.isLauncherPresented {
                    environment.launcherStore.query = ""
                    environment.isLauncherPresented = false
                } else {
                    environment.isLauncherPresented = true
                }
                return true
            case .toggleSettings:
                // ⌘, summons/dismisses the Settings overlay (macOS convention).
                environment.isLauncherPresented = false
                environment.isWorkspaceOverviewPresented = false
                environment.isAppStorePresented = false
                environment.isQuickAskPresented = false
                environment.isSettingsPresented.toggle()
                window?.makeFirstResponder(nil)
                return true
            case .toggleAppStore:
                // Summons/dismisses the App Store overlay.
                environment.isLauncherPresented = false
                environment.isWorkspaceOverviewPresented = false
                environment.isSettingsPresented = false
                environment.isQuickAskPresented = false
                environment.isAppStorePresented.toggle()
                window?.makeFirstResponder(nil)
                return true
            case .newWorkspace:
                environment.workspaceManager.createWorkspace()
                // A hidden workspace's terminal must not keep receiving
                // keystrokes after the switch.
                window?.makeFirstResponder(nil)
                return true
            case .toggleWorkspaceOverview:
                environment.isLauncherPresented = false
                environment.isSettingsPresented = false
                environment.isAppStorePresented = false
                environment.isQuickAskPresented = false
                environment.isWorkspaceOverviewPresented.toggle()
                return true
            case .openQuickAsk:
                environment.isWorkspaceOverviewPresented = false
                environment.isSettingsPresented = false
                environment.isAppStorePresented = false
                if environment.isQuickAskPresented {
                    environment.isQuickAskPresented = false
                } else {
                    environment.isLauncherPresented = false
                    environment.isQuickAskPresented = true
                }
                return true
            case .closeBlock:
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                if let focusedBlockID = layout.focusedBlockID {
                    // Same cue the pane header's ✕ plays — ⌘W was the one
                    // close path without it (mirror of the ⌘M focus-mode fix).
                    environment.sounds.play(.appClose)
                    layout.close(focusedBlockID)
                }
                return true
            case .pushToTalk:
                // Unreachable: intercepted in `handle` above before `perform`
                // is called. Present only for switch exhaustiveness.
                return true
            case .cyclePermissionMode:
                environment.agentPermissionStore.cycle()
                return true
            }
        }
    }
}
