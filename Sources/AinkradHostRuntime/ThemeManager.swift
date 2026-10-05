import AinkradAppKitUI
import Observation
import SwiftUI

/// Holds the active theme, exposes theme tokens, and is the single place the
/// theme is applied: update state and persist. See ADR-0006 Theming Approach.
///
/// Also owns UI font scale/family and an optional custom accent color
/// override (AIN-143 — Settings → Appearance → Typography). `tokens` folds
/// the accent override into the current theme's tokens, so every view that
/// reads `environment.themeManager.tokens` picks up the override live,
/// without knowing an override exists.
@MainActor
@Observable
public final class ThemeManager {
    public private(set) var currentTheme: Theme
    public private(set) var uiFontScale: UIFontScale
    public private(set) var uiFontFamily: UIFontFamily
    public private(set) var accentColorHex: String?
    private let persistence: PersistenceStore

    /// The current theme's skin (accent override is NOT applied to skin — R2).
    public var skin: AinkradSkin {
        ThemeCatalog.shared.themeFile(for: currentTheme.rawValue).skin
    }

    /// The current theme's tokens with the custom accent (if any) applied.
    public var tokens: DesignTokens {
        currentTheme.tokens.overridingAccentPrimary(accentColorHex.map { Color(hex: $0) })
    }

    /// Fired after a theme change is applied + persisted. Used by the app-icon
    /// store to re-apply the Dock icon when the color is Auto. Mirrors
    /// `WorkspaceManager.onStateChange`.
    public var onThemeChange: (() -> Void)?

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.currentTheme = settings.theme
        self.uiFontScale = settings.uiFontScale
        self.uiFontFamily = settings.uiFontFamily
        self.accentColorHex = settings.accentColorHex
        AinkradFont.configure(scale: uiFontScale.multiplier, family: uiFontFamily)
    }

    /// Selecting a theme adopts that theme's own accent — any custom accent
    /// override is cleared, so the accent always follows the theme on switch.
    /// (A custom accent can be re-picked afterward; it sticks until the next
    /// theme change.)
    public func setTheme(_ theme: Theme) {
        currentTheme = theme
        accentColorHex = nil
        persist {
            $0.theme = theme
            $0.accentColorHex = nil
        }
        onThemeChange?()
        Log.settings.info("Theme changed to \(theme.rawValue, privacy: .public)")
    }

    public func setFontScale(_ scale: UIFontScale) {
        uiFontScale = scale
        persist { $0.uiFontScale = scale }
        AinkradFont.configure(scale: uiFontScale.multiplier, family: uiFontFamily)
    }

    public func setFontFamily(_ family: UIFontFamily) {
        uiFontFamily = family
        persist { $0.uiFontFamily = family }
        AinkradFont.configure(scale: uiFontScale.multiplier, family: uiFontFamily)
    }

    /// Sets (or, when `nil`, clears) the custom accent override. Clearing it
    /// restores the current theme's own accent.
    public func setAccentColorHex(_ hex: String?) {
        accentColorHex = hex
        persist { $0.accentColorHex = hex }
    }

    private func persist(_ mutate: (inout GlobalSettings) -> Void) {
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        mutate(&settings)
        persistence.save(settings)
    }
}
