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
