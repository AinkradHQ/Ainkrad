import AinkradAppKitUI
import SwiftUI

/// The app themes. `neonBlue` is first and is the default. The original two
/// (Neon Blue, Cyber Purple) are the brand themes; the rest are well-known
/// palettes ported to full app themes (they drive both the app UI and the
/// terminal's Match-Theme colors). See UI Style Guidelines.
public enum Theme: String, Codable, CaseIterable {
    case neonBlue
    case cyberPurple
    case dracula
    case nord
    case tokyoNight
    case gruvbox
    case solarizedDark

    /// This theme's skin, from its theme file.
    public var skin: AinkradSkin {
        ThemeCatalog.shared.themeFile(for: rawValue).skin
    }

    /// Human-readable name for the theme picker.
    public var displayName: String {
        switch self {
        case .neonBlue: return "Neon Blue"
        case .cyberPurple: return "Cyber Purple"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .tokyoNight: return "Tokyo Night"
        case .gruvbox: return "Gruvbox"
        case .solarizedDark: return "Solarized Dark"
        }
    }

    /// Which app-icon color family this theme uses when the App Icon color is
    /// set to Auto. See App Icon Picker v2 — Design.
    public var iconColorFamily: AppIconColor {
        if let section = ThemeCatalog.shared.hostSection(for: rawValue) {
            return section.iconColorFamily
        }
        switch self {
        case .cyberPurple, .dracula: return .purple
        case .neonBlue, .nord, .tokyoNight, .gruvbox, .solarizedDark: return .blue
        }
    }

    /// Per-theme art direction for the ambient sky. Colors already come from
    /// the `skin`; this tunes *emphasis* so each theme's sky reads distinctly —
    /// Gruvbox a warm ember-forward sunset, Nord a cool misty calm — without
    /// rewriting any effect. See `SkyProfile`.
    public var skyProfile: SkyProfile {
        if let section = ThemeCatalog.shared.hostSection(for: rawValue) {
            return section.skyProfile
        }
        switch self {
        //                             aurora, embers, mist, fireflies, rays
        case .neonBlue: return SkyProfile(1.00, 0.90, 0.90, 1.00, 1.00)
        case .cyberPurple: return SkyProfile(1.25, 0.90, 0.80, 1.10, 1.00)
        case .dracula: return SkyProfile(1.20, 0.85, 0.85, 1.15, 1.00)
        case .nord: return SkyProfile(0.80, 0.70, 1.40, 0.70, 0.90)
        case .tokyoNight: return SkyProfile(1.10, 0.90, 1.10, 1.00, 1.00)
        case .gruvbox: return SkyProfile(0.70, 1.50, 1.00, 1.20, 1.30)
        case .solarizedDark: return SkyProfile(0.90, 0.80, 1.20, 0.80, 1.00)
        }
    }
}

/// Emphasis multipliers that give each theme's ambient sky its own character.
/// Every field scales an effect's baseline strength; `1.0` is unchanged, so
/// `.neutral` reproduces the original look. Colors are unaffected — those come
/// from the skin — this is purely how loud each effect plays.
public struct SkyProfile: Equatable, Hashable, Sendable {
    public let aurora: Double
    public let embers: Double
    public let mist: Double
    public let fireflies: Double
    public let lightRays: Double

    public init(
        _ aurora: Double, _ embers: Double, _ mist: Double,
        _ fireflies: Double, _ lightRays: Double
    ) {
        self.aurora = aurora
        self.embers = embers
        self.mist = mist
        self.fireflies = fireflies
        self.lightRays = lightRays
    }

    public static let neutral = SkyProfile(1, 1, 1, 1, 1)
}

extension AinkradSkin {
    /// One palette colour, resolved: `skin.color(\.accentSecondary)`.
    public func color(_ key: KeyPath<AinkradSkinPalette, AinkradColorToken>) -> Color {
        color(palette[keyPath: key])
    }
}
