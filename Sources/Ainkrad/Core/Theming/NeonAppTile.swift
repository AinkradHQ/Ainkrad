import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The neon app-icon shown in the Launcher, Workspace overview, tile-mode chips,
/// the Block header, App Store, and Settings rows. Drawn live from the active
/// theme's skin, so the glyph and its glow follow whatever theme is
/// current — at any size and for any app (its SF Symbol) — with no baked
/// per-theme art.
///
/// The glyph sits on a TRANSPARENT background (no dark tile) and is sized to
/// nearly fill the frame, in the secondary accent with a soft two-layer neon
/// bloom. A theme whose `host.language.appTile` is `plain` gets a calm tile
/// instead: the glyph on a `skin.shape(cut:)` fill, no bloom. The branch lives
/// here so the call sites stay unchanged; the badge is the same in both forms.
struct NeonAppTile: View {
    /// The app's SF Symbol name (its `AinkradApp.icon`).
    let symbol: String
    let tokens: AinkradSkin
    var size: CGFloat = 32
    /// Unread-count badge, already capped by `SignalBadgeModel.badgeText`.
    /// Defaulted to nil so every existing call site renders exactly as before.
    var badge: String? = nil
    /// Severity of the worst UNREAD event behind the count.
    ///
    /// Nil keeps the old accent. Otherwise the badge takes the severity
    /// colour, because the previous fixed tint rendered GREEN on a count that
    /// is most often failures — a tile saying "three things went wrong" in the
    /// colour of success.
    var badgeStatus: AinkradStatus? = nil

    @Environment(\.ainkradStatusColors) private var statusColors
    /// Opacity, cut and motion come from the skin. Colours stay on `tokens`
    /// until the callers' area PRs drop that parameter (§1c).
    @Environment(\.ainkradSkin) private var skin
    /// Optional so a tree without the host environment (an `ImageRenderer`
    /// snapshot) draws Neon rather than trapping. Read in `body`, so a theme
    /// switch redraws the tile (`homeLanguage` is observed).
    @Environment(AppEnvironment.self) private var environment: AppEnvironment?

    private var badgeTint: Color {
        // Mapped here rather than through `AinkradStatus.color(in:)`: that
        // takes `HostThemeTokens` and the tile carries the host skin.
        switch badgeStatus {
        case .success: return statusColors.success
        case .warning: return statusColors.warning
        case .danger: return statusColors.danger
        // Neutral is an informational count — nothing is wrong, so it keeps
        // the ordinary accent rather than borrowing a status colour.
        case .neutral, .none: return tokens.color(\.accentTertiary)
        // Resilient enum from a library-evolution module: a status added to
        // the SDK later must render rather than fail to build.
        @unknown default: return tokens.color(\.accentTertiary)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch environment?.themeManager.homeLanguage.appTile ?? .neon {
        case .neon:
            Image(systemName: symbol)
                .font(.system(size: size * 0.82, weight: .medium))  // design-lint: allow font-size kit-gap neonGlyphRatio
                .foregroundStyle(tokens.color(\.accentSecondary))
                // Glow scales with the render size so the bloom reads the same at
                // 18pt or 88pt — kept subtle.
                .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o35), radius: size * 0.09)
                .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o16), radius: size * 0.22)
                .frame(width: size, height: size)
        case .plain:
            // Liquid Glass "Clear" app-icon mode: a frosted, see-through glass
            // squircle drawn by the system (highlights, refraction), white glyph.
            let squircle = skin.shape(cut: size * skin.cut.r0_22)
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))  // design-lint: allow font-size kit-gap plainGlyphRatio
                .foregroundStyle(skin.color(.palette("white", 1)))
                // Flattened so a multi-layer symbol (`sparkles`) keeps its tint in a
                // layer-tree capture (`cacheDisplay`).
                .compositingGroup()
                .frame(width: size, height: size)
                .clearGlassTile(in: squircle)
        }
    }

    var body: some View {
        glyph
            // Overlaid rather than in an HStack: the badge must not change the
            // tile's footprint, or a notification would nudge the launcher grid.
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(AinkradFont.mono(size * 0.24, weight: .semibold))
                        .foregroundStyle(tokens.color(\.background))
                        .padding(.horizontal, size * 0.10)
                        .padding(.vertical, size * 0.03)
                        .background(skin.shape(cut: size * skin.cut.r0_10).fill(badgeTint))
                        .shadow(color: badgeTint.opacity(skin.opacity.o60), radius: size * 0.08)
                        .offset(x: size * 0.22, y: -size * 0.12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(skin.motion.springs["sp30_70"].map { skin.animation($0) }, value: badge)
    }
}

extension View {
    /// The system's clear Liquid Glass in `shape` (macOS 26+); a blurred
    /// fill of the same shape before that.
    @ViewBuilder fileprivate func clearGlassTile<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.clear, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
