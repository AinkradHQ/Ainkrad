import AinkradHostRuntime
import SwiftUI

/// An assistant-scoped typography value: the font family + size multiplier the
/// assistant transcript body renders with. It combines the per-assistant
/// override (from `AppAppearanceStore`) with the global Appearance default,
/// WITHOUT touching the global `AinkradFont` static — so only the assistant
/// transcript is affected.
struct SageTypography: Equatable {
    var scale: CGFloat = 1.0
    var family: UIFontFamily = .exo2

    /// Resolve the effective typography: each override value falls back to the
    /// global default when nil.
    static func resolve(
        family: UIFontFamily?, scale: UIFontScale?,
        globalFamily: UIFontFamily, globalScale: UIFontScale
    ) -> SageTypography {
        SageTypography(
            scale: (scale ?? globalScale).multiplier,
            family: family ?? globalFamily)
    }

    /// A resolved SwiftUI `Font` at the given point size, mirroring
    /// `AinkradFont.display` but using this value's scale/family.
    @MainActor
    func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * scale
        guard let fontName = family.fontName else {
            return .system(size: scaled).weight(weight)
        }
        return .custom(fontName, size: scaled).weight(weight)
    }
}
