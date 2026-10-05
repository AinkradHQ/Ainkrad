import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("UIFontScale")
struct UIFontScaleTests {
    @Test("multiplier maps small/medium/large to the documented scale factors")
    func multipliers() {
        #expect(UIFontScale.small.multiplier == 0.9)
        #expect(UIFontScale.medium.multiplier == 1.0)
        #expect(UIFontScale.large.multiplier == 1.15)
    }
}

@Suite("UIFontFamily")
struct UIFontFamilyTests {
    @Test("fontName maps to the bundled face name, or nil for the system font")
    func fontNames() {
        #expect(UIFontFamily.exo2.fontName == "Exo 2")
        #expect(UIFontFamily.jetBrainsMono.fontName == "JetBrains Mono")
        #expect(UIFontFamily.system.fontName == nil)
    }
}

@Suite("DesignTokens.overridingAccentPrimary")
struct DesignTokensAccentOverrideTests {
    @Test("a non-nil color replaces accentPrimary and leaves the other tokens equal")
    func nonNilReplaces() {
        let base = LegacyDesignTokens.neonBlue
        let overridden = base.overridingAccentPrimary(.red)

        #expect(overridden.accentPrimary == .red)
        #expect(overridden.background == base.background)
        #expect(overridden.surface == base.surface)
        #expect(overridden.surfaceElevated == base.surfaceElevated)
        #expect(overridden.accentSecondary == base.accentSecondary)
        #expect(overridden.accentTertiary == base.accentTertiary)
        #expect(overridden.foreground == base.foreground)
    }

    @Test("nil returns an equal copy, unchanged")
    func nilReturnsEqualCopy() {
        let base = LegacyDesignTokens.cyberPurple
        #expect(base.overridingAccentPrimary(nil) == base)
    }
}
