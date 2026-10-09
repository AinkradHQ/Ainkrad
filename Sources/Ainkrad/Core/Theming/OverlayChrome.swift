import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// Shared visual language for the summonable HUD overlays — Launcher,
/// Settings, App Store, Workspace Overview, Quit. Centralizing the backdrop
/// opacity and panel treatment here keeps them reading as one system even
/// though each panel's content differs.
///
/// Both values are skin tokens, read from `AinkradSkin.standard` so the
/// callers in other areas keep compiling as plain statics. Every bundled theme
/// inherits them from `default.theme` (`OverlayChromeTests` checks all 7), so
/// this equals the live skin. Each caller's area PR switches it to
/// `@Environment(\.ainkradSkin)`, which `hudPanelChrome` already reads.
enum OverlayChrome {
    /// Panel corner radius, shared by every overlay's outer frame — `radius.panel`.
    static var cornerRadius: CGFloat { AinkradSkin.standard.radius.panel }
    /// Opacity of the dimming scrim behind a summoned overlay — `chrome.overlay.backdropOpacity`.
    static var backdropOpacity: Double { AinkradSkin.standard.chrome.overlay.backdropOpacity }
}

/// The shared panel finish: a (settings-driven) translucent + optionally
/// blurred background, chamfered clip, and the Cardinal HUD edge-ring +
/// panel glow. Applied to each overlay's outermost panel container. Reads
/// the overlay opacity/blur settings live.
private struct HUDPanelChrome: ViewModifier {
    let tokens: AinkradSkin
    /// How the blur samples what it sits over.
    ///
    /// `.withinWindow` is right for an overlay drawn INSIDE the app window —
    /// it blurs the app content behind it. A panel hosted in its own
    /// `NSPanel` (anything presented via `ainkradFloatingPanel`) has nothing
    /// behind it within that window, so the blur renders as a flat fill and
    /// the panel reads opaque; those need `.behindWindow`.
    let blending: NSVisualEffectView.BlendingMode
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    func body(content: Content) -> some View {
        let store = environment.generalSettingsStore
        content
            .background {
                ZStack {
                    if store.overlayBlurEnabled {
                        // The theme's material (blur, glass or solid). Under blur the
                        // kit's `.panel` level is `.hudWindow`, the material the
                        // host's own blur used — same pixels.
                        AinkradMaterialBackground(level: .panel, blending: blending)
                    }
                    // Under glass the user's opacity is capped at the theme's panel
                    // opacity, so the default (tuned for Neon) can't bury the glass.
                    tokens.color(\.background).opacity(store.overlayOpacity(in: skin))
                }
            }
            .clipShape(skin.shape(cut: skin.radius.panel))
            // Accent border must follow the CHAMFER (the SDK `.ainkradEdgeRing`
            // strokes a RoundedRectangle, which made overlays read as rounded
            // despite the chamfer clip). Stroke the same skin shape so the
            // frame reads as Cardinal HUD. The colours stay on `tokens`, which
            // carry the user's custom accent; the skin's `overlay.edgeFrom/edgeTo`
            // would drop it (theme-foundation fact 2), so only their alphas and
            // the width come from the skin.
            .overlay(
                skin.shape(cut: skin.radius.panel)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tokens.color(\.accentSecondary).opacity(skin.opacity.o55),
                                tokens.color(\.accentPrimary).opacity(skin.opacity.o28),
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: skin.chrome.overlay.edgeWidth)
            )
            .ainkradPanelGlow()
    }
}

extension View {
    /// Applies the shared HUD panel finish (background, clip, border glow,
    /// shadow stack) used by the Launcher, Settings, App Store, Workspace
    /// Overview, and Quit panels.
    func hudPanelChrome(
        tokens: AinkradSkin,
        blending: NSVisualEffectView.BlendingMode = .withinWindow
    ) -> some View {
        modifier(HUDPanelChrome(tokens: tokens, blending: blending))
    }
}

extension AinkradSkin {
    /// 1 when the theme draws targeting brackets, 0 when it turns them off
    /// (`effects.brackets.width` 0, e.g. Glass); multiplies a bracket stroke.
    var bracketStrokeScale: CGFloat { effects.brackets.width > 0 ? 1 : 0 }
}

extension GeneralSettingsStore {
    /// The user's overlay opacity, capped under a glass theme at the theme's
    /// panel opacity: the default (0.94) was tuned for Neon and would bury
    /// Liquid Glass. Every overlay and kit panel reads its fill through this.
    func overlayOpacity(in skin: AinkradSkin) -> Double {
        skin.material.kind == "glass"
            ? min(overlayBackgroundOpacity, skin.material.panelOpacity) : overlayBackgroundOpacity
    }
}
