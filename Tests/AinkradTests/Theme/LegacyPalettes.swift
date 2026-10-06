// design-lint: allow-file hex-color theme palette data, the pre-theme-file literals
import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// The 7 palettes the host shipped as Swift literals before they became theme
/// files, as RRGGBB strings, so the theme files can be checked against them.
enum LegacyPalettes {
    /// Every palette colour, in `table`'s order.
    static var keys: [KeyPath<AinkradSkinPalette, AinkradColorToken>] {
        [
            \.background, \.surface, \.surfaceElevated, \.accentPrimary, \.accentSecondary,
            \.accentTertiary, \.foreground, \.success, \.warning, \.danger,
        ]
    }

    /// A skin's palette resolved in `keys` order.
    static func hexes(_ skin: AinkradSkin) -> [String?] {
        keys.map { skin.color($0).hexString }
    }

    static var table: [Theme: [String]] {
        [
            .neonBlue: ["0A0E17", "111827", "1A2233", "2563EB", "22D3EE", "10B981", "E2E8F0", "3FB950", "E3B341", "F85149"],
            .cyberPurple: ["080814", "141420", "1F182E", "7C1AED", "C084FC", "EC4899", "EDE9FE", "3FB950", "E3B341", "F85149"],
            .dracula: ["1A1B23", "282A36", "343746", "BD93F9", "FF79C6", "50FA7B", "F8F8F2", "50FA7B", "F1FA8C", "FF5555"],
            .nord: ["1B2029", "2E3440", "3B4252", "8FD6EA", "9EC1E8", "A3BE8C", "ECEFF4", "A3BE8C", "EBCB8B", "BF616A"],
            .tokyoNight: ["15161F", "1A1B26", "24283B", "7AA2F7", "BB9AF7", "9ECE6A", "C0CAF5", "9ECE6A", "E0AF68", "F7768E"],
            .gruvbox: ["1D2021", "282828", "3C3836", "FE8019", "FABD2F", "B8BB26", "EBDBB2", "B8BB26", "FABD2F", "FB4934"],
            .solarizedDark: ["002B36", "073642", "0F4A56", "268BD2", "2AA198", "859900", "839496", "859900", "B58900", "DC322F"],
        ]
    }
}
