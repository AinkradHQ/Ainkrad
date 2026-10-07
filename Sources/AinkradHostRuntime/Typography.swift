import CoreText
// design-lint: allow-file font-size theme layer — the host font factory; sizes come from its callers
import SwiftUI

/// Registers the bundled brand fonts (Exo 2, JetBrains Mono — variable
/// TTFs) for this process. Called once from `AinkradHostApp.init`, before any
/// view renders.
public enum FontRegistrar {
    public static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// User-selectable UI text size. `multiplier` scales every `AinkradFont`
/// point size — see AIN-143.
public enum UIFontScale: String, Codable, CaseIterable {
    case small, medium, large

    public var multiplier: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        }
    }
}

/// User-selectable UI typeface. `fontName` is the face `AinkradFont.display`
/// resolves to; `nil` means the system font — see AIN-143.
public enum UIFontFamily: String, Codable, CaseIterable {
    case exo2, jetBrainsMono, system

    public var fontName: String? {
        switch self {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return nil
        }
    }
}

/// The two brand typefaces — see 06 Brand/Brand Identity.md. Exo 2 for
/// display/UI text, JetBrains Mono for data and HUD readouts. Falls back
/// to the system face automatically if registration failed.
///
/// `display`/`mono` honor a shared, `configure(scale:family:)`-set
/// scale + family (see AIN-143 — Settings → Appearance → Typography) so call
/// sites don't need to plumb `ThemeManager` state through every `Font` call.
public enum AinkradFont {
    @MainActor private static var scale: CGFloat = 1.0
    @MainActor private static var family: UIFontFamily = .exo2

    /// Sets the scale/family every subsequent `display`/`mono` call uses.
    /// Called by `ThemeManager` on init and whenever the user changes either
    /// setting, so already-rendered text picks up the new value on the next
    /// re-render.
    @MainActor
    public static func configure(scale: CGFloat, family: UIFontFamily) {
        self.scale = scale
        self.family = family
    }

    @MainActor
    public static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaledSize = size * scale
        guard let fontName = family.fontName else {
            return .system(size: scaledSize).weight(weight)
        }
        return .custom(fontName, size: scaledSize).weight(weight)
    }

    @MainActor
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size * scale).weight(weight)
    }
}
