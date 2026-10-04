// design-lint: allow-file hex-color theme palette data until default.theme (3.3)
import SwiftUI
import AinkradAppKitUI
@testable import AinkradHostRuntime

/// Fixtures of the legacy literal `DesignTokens` palettes, used to verify theme file parity.
public enum LegacyDesignTokens {
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

    public static let solarizedDark = DesignTokens(
        background: Color(hex: "002B36"),
        surface: Color(hex: "073642"),
        surfaceElevated: Color(hex: "0F4A56"),
        accentPrimary: Color(hex: "268BD2"),
        accentSecondary: Color(hex: "2AA198"),
        accentTertiary: Color(hex: "859900"),
        foreground: Color(hex: "839496"),
        success: Color(hex: "859900"),
        warning: Color(hex: "B58900"),
        danger: Color(hex: "DC322F")
    )
}
