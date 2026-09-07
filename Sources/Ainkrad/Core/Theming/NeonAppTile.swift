import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The neon app-icon shown in the Launcher, Workspace overview, tile-mode chips,
/// the Block header, App Store, and Settings rows. Drawn live from the active
/// theme's `DesignTokens`, so the glyph and its glow follow whatever theme is
/// current — at any size and for any app (its SF Symbol) — with no baked
/// per-theme art.
///
/// The glyph sits on a TRANSPARENT background (no dark tile) and is sized to
/// nearly fill the frame, in the secondary accent with a soft two-layer neon
/// bloom.
struct NeonAppTile: View {
    /// The app's SF Symbol name (its `AinkradApp.icon`).
    let symbol: String
    let tokens: DesignTokens
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

    private var badgeTint: Color {
        // Mapped here rather than through `AinkradStatus.color(in:)`: that
        // takes `HostThemeTokens` and the tile carries `DesignTokens`.
        switch badgeStatus {
        case .success: return statusColors.success
        case .warning: return statusColors.warning
        case .danger: return statusColors.danger
        // Neutral is an informational count — nothing is wrong, so it keeps
        // the ordinary accent rather than borrowing a status colour.
        case .neutral, .none: return tokens.accentTertiary
        // Resilient enum from a library-evolution module: a status added to
        // the SDK later must render rather than fail to build.
        @unknown default: return tokens.accentTertiary
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.82, weight: .medium))
            .foregroundStyle(tokens.accentSecondary)
            // Glow scales with the render size so the bloom reads the same at
            // 18pt or 88pt — kept subtle.
            .shadow(color: tokens.accentSecondary.opacity(0.35), radius: size * 0.09)
            .shadow(color: tokens.accentSecondary.opacity(0.16), radius: size * 0.22)
            .frame(width: size, height: size)
            // Overlaid rather than in an HStack: the badge must not change the
            // tile's footprint, or a notification would nudge the launcher grid.
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(AinkradFont.mono(size * 0.24, weight: .semibold))
                        .foregroundStyle(tokens.background)
                        .padding(.horizontal, size * 0.10)
                        .padding(.vertical, size * 0.03)
                        .background(ChamferShape(cut: size * 0.10).fill(badgeTint))
                        .shadow(color: badgeTint.opacity(0.6), radius: size * 0.08)
                        .offset(x: size * 0.22, y: -size * 0.12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: badge)
    }
}
