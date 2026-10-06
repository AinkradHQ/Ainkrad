import AinkradAppKitUI
import AppKit
import Observation
import SwiftUI

/// Holds the active theme, exposes its skin, and is the single place the
/// theme is applied: update state and persist. See ADR-0006 Theming Approach.
///
/// Also owns UI font scale/family and an optional custom accent color
/// override (AIN-143 — Settings → Appearance → Typography). `hostSkin` folds
/// the accent override into the current theme's skin, so every host view
/// that reads its colours from `environment.themeManager.hostSkin` picks up
/// the override live, without knowing an override exists.
@MainActor
@Observable
public final class ThemeManager {
    public private(set) var currentTheme: Theme
    public private(set) var uiFontScale: UIFontScale
    public private(set) var uiFontFamily: UIFontFamily
    public private(set) var accentColorHex: String?
    private let persistence: PersistenceStore

    /// The current theme's skin (accent override is NOT applied to skin — R2).
    /// This is what the root injects, so AppKit components never see the
    /// custom accent; that quirk is kept for parity until the themes milestone.
    public var skin: AinkradSkin { currentTheme.skin }

    /// `skin` with the custom accent (if any) as `palette.accentPrimary`. Host
    /// chrome reads its colours here, never from the environment's skin.
    /// Stored, not computed: the skin is a 9 KB copy-on-write box, and views
    /// read this many times per body.
    public private(set) var hostSkin: AinkradSkin

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
        self.hostSkin = Self.hostSkin(settings.theme, accentHex: settings.accentColorHex)
        AinkradFont.configure(scale: uiFontScale.multiplier, family: uiFontFamily)
    }

    /// Selecting a theme adopts that theme's own accent — any custom accent
    /// override is cleared, so the accent always follows the theme on switch.
    /// (A custom accent can be re-picked afterward; it sticks until the next
    /// theme change.)
    public func setTheme(_ theme: Theme) {
        currentTheme = theme
        accentColorHex = nil
        hostSkin = Self.hostSkin(theme, accentHex: nil)
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
        hostSkin = Self.hostSkin(currentTheme, accentHex: hex)
        persist { $0.accentColorHex = hex }
    }

    /// Sets the custom accent from a picked colour; one that can't be
    /// resolved to sRGB clears it.
    public func setAccentColor(_ color: Color) {
        setAccentColorHex(color.hexString)
    }

    private static func hostSkin(_ theme: Theme, accentHex: String?) -> AinkradSkin {
        var skin = theme.skin
        if let accentHex, let value = UInt32(accentHex.trimmingCharacters(in: ["#"]), radix: 16) {
            skin.palette.accentPrimary = .hex(
                Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255, 1)
        }
        return skin
    }

    private func persist(_ mutate: (inout GlobalSettings) -> Void) {
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        mutate(&settings)
        persistence.save(settings)
    }
}

extension Color {
    /// The color as an uppercase 6-digit RRGGBB hex string (no `#`), or nil if
    /// it can't be resolved to sRGB components — the stored form of the
    /// custom accent, and how Scry hands theme colours to its web views.
    public var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}
