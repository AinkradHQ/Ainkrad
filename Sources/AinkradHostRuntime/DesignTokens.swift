// design-lint: allow-file hex-color theme palette data until default.theme (3.3)
import SwiftUI

/// Semantic color tokens for one theme. Views read these — never a raw hex
/// literal — so a view is automatically correct in both themes. See
/// WorkShop/Ainkrad/06 Brand/Color Tokens.md for the source values.
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

    public static let neonBlue = DesignTokens(
        background: Color(hex: "0A0E17"),
        surface: Color(hex: "111827"),
        surfaceElevated: Color(hex: "1A2233"),
        accentPrimary: Color(hex: "2563EB"),
        accentSecondary: Color(hex: "22D3EE"),
        accentTertiary: Color(hex: "10B981"),
        foreground: Color(hex: "E2E8F0"),
        success: Color(hex: "3FB950"),
        warning: Color(hex: "E3B341"),
        danger: Color(hex: "F85149")
    )

    public static let cyberPurple = DesignTokens(
        background: Color(hex: "080814"),
        surface: Color(hex: "141420"),
        surfaceElevated: Color(hex: "1F182E"),
        accentPrimary: Color(hex: "7C1AED"),
        accentSecondary: Color(hex: "C084FC"),
        accentTertiary: Color(hex: "EC4899"),
        foreground: Color(hex: "EDE9FE"),
        success: Color(hex: "3FB950"),
        warning: Color(hex: "E3B341"),
        danger: Color(hex: "F85149")
    )

    // Well-known palettes ported to full app themes (each also drives the
    // terminal's Match-Theme colors — see TerminalMatchThemePalette).

    // Dracula — deepened background (official #282A36 becomes the `surface`)
    // so the vivid purple/pink accents glow; tertiary corrected to the
    // canonical Dracula green (success), not cyan.
    public static let dracula = DesignTokens(
        background: Color(hex: "1A1B23"),
        surface: Color(hex: "282A36"),
        surfaceElevated: Color(hex: "343746"),
        accentPrimary: Color(hex: "BD93F9"),
        accentSecondary: Color(hex: "FF79C6"),
        accentTertiary: Color(hex: "50FA7B"),
        foreground: Color(hex: "F8F8F2"),
        success: Color(hex: "50FA7B"),
        warning: Color(hex: "F1FA8C"),
        danger: Color(hex: "FF5555")
    )

    // Nord — polar-night background pushed darker than nord0 (which becomes
    // `surface`) so the frost accents stop looking washed out; accents lifted
    // toward luminous frost while staying in the Nord blue family.
    public static let nord = DesignTokens(
        background: Color(hex: "1B2029"),
        surface: Color(hex: "2E3440"),
        surfaceElevated: Color(hex: "3B4252"),
        accentPrimary: Color(hex: "8FD6EA"),
        accentSecondary: Color(hex: "9EC1E8"),
        accentTertiary: Color(hex: "A3BE8C"),
        foreground: Color(hex: "ECEFF4"),
        success: Color(hex: "A3BE8C"),
        warning: Color(hex: "EBCB8B"),
        danger: Color(hex: "BF616A")
    )

    // Tokyo Night — background nudged darker; tertiary corrected to the
    // canonical Tokyo Night green (success) rather than cyan.
    public static let tokyoNight = DesignTokens(
        background: Color(hex: "15161F"),
        surface: Color(hex: "1A1B26"),
        surfaceElevated: Color(hex: "24283B"),
        accentPrimary: Color(hex: "7AA2F7"),
        accentSecondary: Color(hex: "BB9AF7"),
        accentTertiary: Color(hex: "9ECE6A"),
        foreground: Color(hex: "C0CAF5"),
        success: Color(hex: "9ECE6A"),
        warning: Color(hex: "E0AF68"),
        danger: Color(hex: "F7768E")
    )

    // Gruvbox — "hard dark" background (bg0_h) so the warm orange/yellow
    // accents read against a properly dark base.
    public static let gruvbox = DesignTokens(
        background: Color(hex: "1D2021"),
        surface: Color(hex: "282828"),
        surfaceElevated: Color(hex: "3C3836"),
        accentPrimary: Color(hex: "FE8019"),
        accentSecondary: Color(hex: "FABD2F"),
        accentTertiary: Color(hex: "B8BB26"),
        foreground: Color(hex: "EBDBB2"),
        success: Color(hex: "B8BB26"),
        warning: Color(hex: "FABD2F"),
        danger: Color(hex: "FB4934")
    )

    // Solarized Dark — accent blue brightened for presence and, crucially,
    // the foreground lifted off base0 (#93A1A1, famously low-contrast) to a
    // legible bright tone while keeping the Solarized cast.
    public static let solarizedDark = DesignTokens(
        background: Color(hex: "002B36"),
        surface: Color(hex: "073642"),
        surfaceElevated: Color(hex: "0E4A5A"),
        accentPrimary: Color(hex: "2E9EF0"),
        accentSecondary: Color(hex: "2AA198"),
        accentTertiary: Color(hex: "A0B82E"),
        foreground: Color(hex: "C6D2D2"),
        success: Color(hex: "859900"),
        warning: Color(hex: "B58900"),
        danger: Color(hex: "DC322F")
    )

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
