import SwiftUI
import AinkradAppKit

/// The compiled-in Sage app — the tiled AgentKit chat surface. It is
/// host-embedded rather than a real plugin: its views read `AppEnvironment`
/// directly via `@Environment(AppEnvironment.self)` (same as the Settings
/// sections), so `host` is unused here beyond satisfying the registration
/// contract shared with dynamically-loaded `AinkradApp`s.
enum SageApp: AinkradApp {
    static let id = "sage"
    static let displayName = "Sage"
    static let icon = "sparkles"

    static func makeRootView(host: HostServices) -> AnyView {
        makeRootView(host: host, mode: .advanced)
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(SageSettingsView())
    }

    /// The Sage's window fill for a given surface opacity. Translucent
    /// (so `TileLayoutView.hasTranslucentPane` triggers and the header unifies
    /// with the body) only when the user has dialed opacity below 1; `nil`
    /// means opaque — no backdrop, today's look. Pure + host-independent so it
    /// is unit-testable without `AppEnvironment`.
    static func surfaceFill(opacity: Double, base: Color) -> Color? {
        opacity < 1 ? base.opacity(opacity) : nil
    }
}

/// Generation 11: Sage's basic mode is one prompt and its answer.
///
/// `showsHeader: false` is not a new configuration invented for this — it is
/// the one `QuickAskOverlayView` already uses, and it already gates the history
/// sidebar as well as the header. So basic mode is the Quick Ask surface made
/// available as a mode, rather than a third rendering of the same transcript.
extension SageApp: AinkradAppModes {
    static func makeRootView(host: HostServices, mode: PluginMode) -> AnyView {
        switch mode {
        case .basic:
            // Autofocused for the same reason Quick Ask is: you opened it to
            // type, and a composer you must click first is the friction this
            // mode exists to remove.
            return AnyView(SageRootView(showsHeader: false, autoFocusComposer: true))
        case .advanced:
            return AnyView(SageRootView())
        // Resilient enum: fall back to advanced, never to a stripped view for a
        // mode this build does not understand.
        @unknown default:
            return AnyView(SageRootView())
        }
    }
}
