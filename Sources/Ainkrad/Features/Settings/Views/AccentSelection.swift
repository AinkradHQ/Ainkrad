import Foundation

/// Which accent swatch reads as the current one.
///
/// Pure, so the setup wizard's swatch row is testable. It accounts for
/// INHERITANCE: `accentColorHex` is nil until the user picks an accent
/// explicitly, so keying selection only off the override left the row with
/// nothing selected on arrival — while the workspace behind it visibly had an
/// accent.
enum AccentSelection {
    /// - Parameters:
    ///   - swatchHex: the swatch being drawn.
    ///   - overrideHex: `ThemeManager.accentColorHex`; nil means "inherit".
    ///   - themeAccentHex: the current theme's own `accentPrimary`.
    static func isSelected(
        swatchHex: String,
        overrideHex: String?,
        themeAccentHex: String
    ) -> Bool {
        if let overrideHex {
            return overrideHex.caseInsensitiveCompare(swatchHex) == .orderedSame
        }
        return themeAccentHex.caseInsensitiveCompare(swatchHex) == .orderedSame
    }
}
