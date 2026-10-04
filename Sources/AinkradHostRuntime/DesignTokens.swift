import SwiftUI
import AinkradAppKitUI

/// Semantic color tokens for one theme. Views read these — never a raw hex
/// literal — so a view is automatically correct in both themes.
public struct DesignTokens: Equatable, Sendable {
    public let background: Color
    public let surface: Color
    public let surfaceElevated: Color
    public let accentPrimary: Color
    public let accentSecondary: Color
    public let accentTertiary: Color
    public let foreground: Color
    public let success: Color
    public let warning: Color
    public let danger: Color

    public init(background: Color, surface: Color, surfaceElevated: Color,
                accentPrimary: Color, accentSecondary: Color, accentTertiary: Color,
                foreground: Color, success: Color, warning: Color, danger: Color) {
        self.background = background
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.accentPrimary = accentPrimary
        self.accentSecondary = accentSecondary
        self.accentTertiary = accentTertiary
        self.foreground = foreground
        self.success = success
        self.warning = warning
        self.danger = danger
    }

    public init(skin: AinkradSkin) {
        let palette = skin.palette
        self.background = skin.color(palette.background)
        self.surface = skin.color(palette.surface)
        self.surfaceElevated = skin.color(palette.surfaceElevated)
        self.accentPrimary = skin.color(palette.accentPrimary)
        self.accentSecondary = skin.color(palette.accentSecondary)
        self.accentTertiary = skin.color(palette.accentTertiary)
        self.foreground = skin.color(palette.foreground)
        self.success = skin.color(palette.success)
        self.warning = skin.color(palette.warning)
        self.danger = skin.color(palette.danger)
    }

    /// Returns a copy with `accentPrimary` replaced by `color`, or `self`
    /// unchanged when `color` is `nil` — see AIN-143 (custom accent color).
    /// `DesignTokens`' fields are all `let`, so this builds a new instance
    /// rather than mutating in place.
    public func overridingAccentPrimary(_ color: Color?) -> DesignTokens {
        guard let color else { return self }
        return DesignTokens(
            background: background,
            surface: surface,
            surfaceElevated: surfaceElevated,
            accentPrimary: color,
            accentSecondary: accentSecondary,
            accentTertiary: accentTertiary,
            foreground: foreground,
            success: success,
            warning: warning,
            danger: danger
        )
    }
}
