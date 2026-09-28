import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The compiled-in Hoard app — a keyboard-driven, git-aware file browser.
/// Host-embedded rather than a real plugin (same as `SageApp` and
/// `ScryApp`): its views read `AppEnvironment` directly via
/// `@Environment(AppEnvironment.self)`, so `host` is unused here beyond
/// satisfying the registration contract shared with dynamically-loaded
/// `AinkradApp`s.
enum HoardApp: AinkradApp {
    static let id = "hoard"
    static let displayName = "Hoard"
    static let icon = "folder"

    static func makeRootView(host: HostServices) -> AnyView {
        makeRootView(host: host, mode: .advanced)
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(EmptyView())
    }

    /// The pane's window fill for a given surface opacity — the same contract
    /// `SageApp` implements, and the mechanism that makes a pane
    /// translucent at all.
    ///
    /// Returning a sub-opaque color is what drives the whole chain:
    /// `TileLayoutView.hasTranslucentPane` then renders the shared blurred
    /// sky+island backdrop behind the pane, and `BlockView.headerBackground`
    /// adopts this same fill so the title bar is one continuous surface with
    /// the body instead of an opaque bar sitting on glass. `nil` means opaque —
    /// no backdrop, no cost. Pure + host-independent so it is unit-testable
    /// without `AppEnvironment`.
    static func surfaceFill(opacity: Double, base: Color) -> Color? {
        opacity < 1 ? base.opacity(opacity) : nil
    }

    /// Hoard' own settings. Declared as real fields rather than a wrapped view:
    /// the `nil` path makes `AppSettingsCatalog` fall back to wrapping
    /// `makeSettingsView` in a `.custom` field, which is the wrap-a-view decay
    /// that `SettingsKitCompositionTests`' ratchet rejects.
    static func settingsCatalog(host: HostServices) -> SettingsPage? {
        // Built by `HoardSettingsCatalog` against `AppEnvironment`, which this
        // static entry point cannot see. The host calls the environment-aware
        // builder directly; this returns the shape with no groups so the page
        // still exists and stays searchable if that wiring is ever bypassed.
        SettingsPage(
            path: SettingsPath(["app", id]),
            title: displayName,
            icon: icon,
            group: .builtInApps,
            order: 0,
            groups: [],
            appID: id
        )
    }
}

/// Generation 11: Hoard's basic mode is one directory — no sidebar, no tabs, no
/// filter, no preview.
///
/// Discovered by the cast in `RegisteredApp.builtIn`, the same one that finds
/// `AinkradAppMCP`. A built-in takes that path rather than `PluginLoader`'s,
/// which is why the cast had to be added in both places.
extension HoardApp: AinkradAppModes {
    static func makeRootView(host: HostServices, mode: PluginMode) -> AnyView {
        switch mode {
        case .basic:    return AnyView(HoardRootView(mode: .basic))
        case .advanced: return AnyView(HoardRootView(mode: .advanced))
        // Resilient enum: fall back to advanced, never to a stripped view for a
        // mode this build does not understand.
        @unknown default: return AnyView(HoardRootView(mode: .advanced))
        }
    }
}
