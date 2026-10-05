import Testing

@testable import Ainkrad

@Suite("Accent swatch selection")
struct AccentSelectionTests {
    @Test("an explicit override selects its own swatch")
    func explicitOverride() {
        #expect(
            AccentSelection.isSelected(
                swatchHex: "#FF0000",
                overrideHex: "#FF0000",
                themeAccentHex: "#00FF00"))
    }

    @Test("an explicit override deselects every other swatch")
    func explicitOverrideExcludesOthers() {
        #expect(
            !AccentSelection.isSelected(
                swatchHex: "#00FF00",
                overrideHex: "#FF0000",
                themeAccentHex: "#00FF00"))
    }

    /// The bug this fixes: `accentColorHex` is nil until the user picks an
    /// accent explicitly, and the old check keyed only off that — so on arrival
    /// NOTHING rendered as selected even though the workspace visibly had an
    /// accent.
    @Test("with no override the theme's own accent is the selected one")
    func inheritedFromTheme() {
        #expect(
            AccentSelection.isSelected(
                swatchHex: "#00FF00",
                overrideHex: nil,
                themeAccentHex: "#00FF00"))
        #expect(
            !AccentSelection.isSelected(
                swatchHex: "#FF0000",
                overrideHex: nil,
                themeAccentHex: "#00FF00"))
    }

    @Test("hex comparison ignores case")
    func caseInsensitive() {
        #expect(
            AccentSelection.isSelected(
                swatchHex: "#ff0000",
                overrideHex: "#FF0000",
                themeAccentHex: "#00FF00"))
    }
}
