import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("Theme")
struct ThemeTests {
    @Test("neonBlue is the first case (the default theme)")
    func neonBlueIsDefault() {
        #expect(Theme.allCases.first == .neonBlue)
    }

    @Test("the brand themes plus the ported well-known palettes are present")
    func allThemesPresent() {
        #expect(Theme.allCases.count == 7)
        for theme in [Theme.cyberPurple, .dracula, .nord, .tokyoNight, .gruvbox, .solarizedDark] {
            #expect(Theme.allCases.contains(theme))
        }
    }

    @Test("every theme resolves to a distinct background token")
    func everyThemeResolves() {
        var backgrounds = Set<Color>()
        for theme in Theme.allCases { backgrounds.insert(theme.tokens.background) }
        #expect(backgrounds.count == Theme.allCases.count)
    }
}

@Suite("DesignTokens")
struct DesignTokensTests {
    @Test("Neon Blue tokens match the documented hex values")
    func neonBlueMatchesDocumentedValues() {
        let tokens = LegacyDesignTokens.neonBlue
        #expect(tokens.background == Color(hex: "0A0E17"))
        #expect(tokens.surface == Color(hex: "111827"))
        #expect(tokens.surfaceElevated == Color(hex: "1A2233"))
        #expect(tokens.accentPrimary == Color(hex: "2563EB"))
        #expect(tokens.accentSecondary == Color(hex: "22D3EE"))
        #expect(tokens.accentTertiary == Color(hex: "10B981"))
        #expect(tokens.foreground == Color(hex: "E2E8F0"))
    }

    @Test("Cyber Purple tokens match the documented hex values")
    func cyberPurpleMatchesDocumentedValues() {
        let tokens = LegacyDesignTokens.cyberPurple
        #expect(tokens.background == Color(hex: "080814"))
        #expect(tokens.surface == Color(hex: "141420"))
        #expect(tokens.surfaceElevated == Color(hex: "1F182E"))
        #expect(tokens.accentPrimary == Color(hex: "7C1AED"))
        #expect(tokens.accentSecondary == Color(hex: "C084FC"))
        #expect(tokens.accentTertiary == Color(hex: "EC4899"))
        #expect(tokens.foreground == Color(hex: "EDE9FE"))
    }

    /// The bridge (`DesignTokens(skin:)` over each theme file) must equal the
    /// literal palettes the host shipped before the skin, for all 7 themes —
    /// every area still reads colours through `DesignTokens` (5A §1c).
    @Test("Theme.tokens, bridged from the skin, equals today's palette for all 7 themes")
    func themeResolvesToMatchingPalette() {
        let legacy: [Theme: DesignTokens] = [
            .neonBlue: LegacyDesignTokens.neonBlue,
            .cyberPurple: LegacyDesignTokens.cyberPurple,
            .dracula: LegacyDesignTokens.dracula,
            .nord: LegacyDesignTokens.nord,
            .tokyoNight: LegacyDesignTokens.tokyoNight,
            .gruvbox: LegacyDesignTokens.gruvbox,
            .solarizedDark: LegacyDesignTokens.solarizedDark,
        ]
        #expect(Set(legacy.keys) == Set(Theme.allCases))
        for theme in Theme.allCases {
            #expect(theme.tokens == legacy[theme], "\(theme.rawValue)")
        }
    }
}
