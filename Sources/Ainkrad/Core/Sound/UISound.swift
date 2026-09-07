/// Every UI sound effect Ainkrad can play (AIN-108) — a sci-fi menu-chime
/// family (original synthesized audio; see `scripts/gen-ui-sounds.py`), not
/// any copyrighted sound. This is the ONE place event→asset mapping lives:
/// `resourceName` is the bundled wav's base-name, so swapping the audio for
/// a given event later only ever touches this file.
enum UISound: String, CaseIterable {
    /// The Ainkrad app itself starting up / quitting (launch/quit) — distinct
    /// from `overlayOpen`/`overlayClose`, which are for the in-app HUD
    /// overlays (Launcher, Settings, App Store, Workspace Overview).
    case appLaunch
    case appQuit
    case overlayOpen
    case overlayClose
    /// An app (Block) opening/closing within a workspace's tile layout.
    case appOpen
    case appClose
    case workspaceSwitch
    case focusMode
    case install
    case uninstall
    case toggle
    case confirm
    case error
    // Notifications get their own family rather than borrowing the three
    // above. A notification's whole job is to say WHICH kind of thing
    // happened before the user has read a word, and three reused interface
    // clicks cannot do that.
    case signalArrive
    case signalWarn
    case signalFail
    case signalUrgent
    case signalResolve

    /// The bundled wav's base-name (without extension), under
    /// `Resources/Sounds/`.
    var resourceName: String { rawValue }

    /// Human-readable event name for the Settings → General per-sound list.
    var displayName: String {
        switch self {
        case .appLaunch: return "App Launch"
        case .appQuit: return "App Quit"
        case .overlayOpen: return "Overlay Open"
        case .overlayClose: return "Overlay Close"
        case .appOpen: return "Pane Open"
        case .appClose: return "Pane Close"
        case .workspaceSwitch: return "Workspace Switch"
        case .focusMode: return "Focus Mode Toggle"
        case .install: return "Install"
        case .uninstall: return "Uninstall"
        case .toggle: return "Toggle"
        case .confirm: return "Confirm"
        case .error: return "Error"
        case .signalArrive: return "Notification"
        case .signalWarn: return "Notification — Warning"
        case .signalFail: return "Notification — Failure"
        case .signalUrgent: return "Notification — Urgent"
        case .signalResolve: return "Notification — Resolved"
        }
    }

    /// One-line description of when the event fires, for the settings row.
    var eventDescription: String {
        switch self {
        case .appLaunch: return "Ainkrad starts up."
        case .appQuit: return "Ainkrad quits."
        case .overlayOpen: return "A HUD overlay (Launcher, Settings, …) opens."
        case .overlayClose: return "A HUD overlay closes."
        case .appOpen: return "An app opens in the tile layout."
        case .appClose: return "An app pane closes."
        case .workspaceSwitch: return "Switching between workspaces."
        case .focusMode: return "Entering or leaving Focus Mode (⌘M)."
        case .install: return "An app installs from the App Store."
        case .uninstall: return "An app is uninstalled."
        case .toggle: return "An app is enabled or disabled."
        case .confirm: return "A confirmation action."
        case .error: return "Something goes wrong."
        case .signalArrive: return "A notification arrives."
        case .signalWarn: return "A warning notification arrives."
        case .signalFail: return "A failure notification arrives."
        case .signalUrgent: return "Something is waiting on you."
        case .signalResolve: return "A failure is followed by a success."
        }
    }
}

extension UISound: Identifiable {
    var id: String { rawValue }
}
