import AinkradAppKitUI
import AppKit
import Observation
import SwiftUI

/// Holds the active theme (a design language) and colour scheme, composes
/// their skin, and is the single place either is applied: update state and
/// persist. See ADR-0006 Theming Approach.
///
/// Also owns UI font scale/family and an optional custom accent color
/// override (AIN-143 — Settings → Appearance → Typography). `hostSkin` folds
/// the accent override into the current theme's skin, so every host view
/// that reads its colours from `environment.themeManager.hostSkin` picks up
/// the override live, without knowing an override exists.
@MainActor
@Observable
public final class ThemeManager {
    /// The stored theme id. Kept even when it is not installed (it resolves
    /// to Neon meanwhile), so a reinstalled store theme comes back.
    public private(set) var currentThemeID: String
    /// Light or dark, as composed: the system's (or `-AinkradAppearance`'s)
    /// when the theme has that variant, else the variant it has (Neon: dark).
    public private(set) var appearance: ThemeAppearance
    public private(set) var uiFontScale: UIFontScale
    public private(set) var uiFontFamily: UIFontFamily
    public private(set) var accentColorHex: String?
    private var colorSchemeDark: String?
    private var colorSchemeLight: String?
    private let persistence: PersistenceStore
    @ObservationIgnored public let catalog: ThemeCatalog
    @ObservationIgnored private let systemAppearance: any SystemAppearanceSource

    /// The composed skin of (theme, scheme, appearance); its `id` is the scheme
    /// id. The accent override is NOT applied here (R2): this is what the root
    /// injects, so AppKit components never see the custom accent.
    public private(set) var skin: AinkradSkin

    /// `skin` with the custom accent (if any) as `palette.accentPrimary`. Host
    /// chrome reads its colours here, never from the environment's skin.
    /// Stored, not computed: the skin is a 9 KB copy-on-write box, and views
    /// read this many times per body.
    public private(set) var hostSkin: AinkradSkin

    /// Sky emphasis and Auto app-icon family of the composed skin.
    public private(set) var skyProfile: SkyProfile
    public private(set) var iconColorFamily: AppIconColor
    /// `"<variant>|<scheme>"` — what the composed skin was built from.
    public private(set) var composedKey: String
    /// The resolved home keys of the composed theme (layout, sky, island art,
    /// pane backdrop, app tile); Neon's when the theme sets none.
    public private(set) var homeLanguage: HomeLanguage
    /// The resolved theme's own scheme for the current appearance.
    public private(set) var defaultColorSchemeID: String
    private var variantID: String

    /// Fired after a theme change is applied + persisted. Used by the app-icon
    /// store to re-apply the Dock icon when the color is Auto. Mirrors
    /// `WorkspaceManager.onStateChange`.
    public var onThemeChange: (() -> Void)?

    public init(
        persistence: PersistenceStore, catalog: ThemeCatalog = ThemeCatalog(),
        systemAppearance: any SystemAppearanceSource = LiveSystemAppearance()
    ) {
        self.persistence = persistence
        self.catalog = catalog
        self.systemAppearance = systemAppearance
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.currentThemeID = settings.theme
        self.colorSchemeDark = settings.colorSchemeDark
        self.colorSchemeLight = settings.colorSchemeLight
        self.uiFontScale = settings.uiFontScale
        self.uiFontFamily = settings.uiFontFamily
        self.accentColorHex = settings.accentColorHex
        let appearance = Self.appearance(catalog, of: settings.theme, wanted: systemAppearance.current)
        self.appearance = appearance
        let resolved = Self.resolve(
            catalog: catalog, themeID: settings.theme, appearance: appearance,
            storedScheme: appearance == .dark ? settings.colorSchemeDark : settings.colorSchemeLight)
        self.skin = resolved.skin
        self.hostSkin = Self.hostSkin(resolved.skin, accentHex: settings.accentColorHex)
        self.skyProfile = resolved.host.skyProfile
        self.iconColorFamily = resolved.host.iconColorFamily
        self.composedKey = resolved.key
        self.homeLanguage = HomeLanguage.resolve(resolved.host.language).home
        self.defaultColorSchemeID = resolved.defaultScheme
        self.variantID = resolved.variantID
        AinkradFont.configure(scale: uiFontScale.multiplier, family: uiFontFamily)
        systemAppearance.observe { [weak self] in self?.systemAppearanceChanged() }
    }

    /// Recomposes only when the composed appearance actually flips; the
    /// catalog caches composed skins, so flipping back does not decode again.
    private func systemAppearanceChanged() {
        let wanted = launchAppearance ?? systemAppearance.current
        guard Self.appearance(catalog, of: currentThemeID, wanted: wanted) != appearance else { return }
        applyChange(clearingAccent: false)
    }

    /// The explicit scheme choice for one appearance; `nil` = the theme's default.
    public func colorSchemeID(for appearance: ThemeAppearance) -> String? {
        appearance == .dark ? colorSchemeDark : colorSchemeLight
    }

    /// Colour schemes for the current appearance, in picker order.
    public var colorSchemes: [ThemeColorScheme] { colorSchemes(for: appearance) }

    /// Colour schemes for `appearance`, in picker order.
    public func colorSchemes(for appearance: ThemeAppearance) -> [ThemeColorScheme] {
        Self.pickerOrdered(catalog.schemes(for: appearance))
    }

    /// Installed themes (design languages), sorted by name.
    public var themes: [(id: String, name: String)] { catalog.languages.map { ($0.id, $0.name) } }

    /// The appearances installed theme `id` has a variant for, dark first.
    public func appearances(ofTheme id: String) -> [ThemeAppearance] {
        let found = Set(catalog.variants(of: id).values.compactMap { $0.hostSection?.language?.appearance })
        return ThemeAppearance.allCases.filter(found.contains)
    }

    /// The theme in use: the stored id, or Neon while that one is not installed.
    public var activeThemeID: String {
        catalog.loadedThemes[variantID]?.hostSection?.language?.id ?? currentThemeID
    }

    /// The active theme's own scheme at `appearance`; nil when the theme has
    /// no variant at that appearance (Neon has no light one).
    public func defaultColorSchemeID(for appearance: ThemeAppearance) -> String? {
        Self.variant(catalog, of: activeThemeID, at: appearance)?.language.defaultColorScheme
    }

    /// Theme and colour-scheme load problems, one line each; warnings are labelled.
    public var catalogIssues: [String] { catalog.issues.map(\.description) }
    /// How many of `catalogIssues` are files that could not load (not warnings).
    public var catalogFailureCount: Int { catalog.issues.filter { !$0.isWarning }.count }

    /// The current theme variant coloured by `schemeID` (a preview swatch), or
    /// nil when that scheme is not installed. Does not change the selection.
    public func skin(forScheme schemeID: String) -> AinkradSkin? {
        catalog.compose(themeVariant: variantID, scheme: schemeID)?.skin
    }

    /// Today's order of the seven bundled schemes, so the scheme pickers read
    /// as before. Other schemes follow by name.
    // ponytail: fixed rank for the bundled seven; a scheme file could carry its own order if that matters.
    public static func pickerOrdered(_ schemes: [ThemeColorScheme]) -> [ThemeColorScheme] {
        let bundled = ["neonBlue", "cyberPurple", "dracula", "nord", "tokyoNight", "gruvbox", "solarizedDark"]
        func rank(_ id: String) -> Int { bundled.firstIndex(of: id) ?? bundled.count }
        return schemes.sorted { (rank($0.id), $0.name) < (rank($1.id), $1.name) }
    }

    /// Selecting a theme adopts that theme's own accent — any custom accent
    /// override is cleared, so the accent always follows the theme on switch.
    /// An explicit colour scheme is kept per appearance while it is still
    /// installed (otherwise the theme's default applies), and the theme's
    /// typeface is adopted (R9) — the user can pick another afterwards.
    public func setTheme(_ id: String) {
        // Re-picking the current theme must not reset the user's accent or typeface.
        guard id != currentThemeID else { return }
        currentThemeID = id
        func kept(_ scheme: String?, _ appearance: ThemeAppearance) -> String? {
            scheme.flatMap { scheme in catalog.schemes(for: appearance).contains { $0.id == scheme } ? scheme : nil }
        }
        colorSchemeDark = kept(colorSchemeDark, .dark)
        colorSchemeLight = kept(colorSchemeLight, .light)
        if let font = catalog.languages.first(where: { $0.id == id })?.fontFamily {
            if let family = UIFontFamily(rawValue: font) {
                uiFontFamily = family
                AinkradFont.configure(scale: uiFontScale.multiplier, family: family)
            } else {
                Log.settings.error("Theme \(id, privacy: .public) names unknown font family \(font, privacy: .public)")
            }
        }
        persist {
            $0.theme = id
            $0.colorSchemeDark = colorSchemeDark
            $0.colorSchemeLight = colorSchemeLight
            $0.uiFontFamily = uiFontFamily
            $0.accentColorHex = nil
        }
        applyChange()
        Log.settings.info("Theme changed to \(id, privacy: .public)")
    }

    /// Selecting a colour scheme also adopts its accent (today's rule). `nil`
    /// clears the choice back to the theme's default.
    public func setColorScheme(_ id: String?, for appearance: ThemeAppearance) {
        switch appearance {
        case .dark: colorSchemeDark = id
        case .light: colorSchemeLight = id
        }
        persist {
            switch appearance {
            case .dark: $0.colorSchemeDark = id
            case .light: $0.colorSchemeLight = id
            }
            $0.accentColorHex = nil
        }
        applyChange()
        Log.settings.info(
            "Colour scheme (\(appearance.rawValue, privacy: .public)) changed to \(id ?? "default", privacy: .public)")
    }

    /// Debug launch override (`-AinkradTheme`, `-AinkradColorScheme`,
    /// `-AinkradAppearance`): applied in memory only, never persisted, and the
    /// custom accent is kept. An id that is not installed is logged and ignored.
    public func applyLaunchOverride(theme: String?, colorScheme: String?, appearance requested: ThemeAppearance?) {
        if let theme {
            if catalog.languages.contains(where: { $0.id == theme }) {
                currentThemeID = theme
            } else {
                Log.settings.error("DEBUG launch arg: unknown AinkradTheme '\(theme, privacy: .public)'")
            }
        }
        launchAppearance = requested
        // The scheme is checked against the appearance this override composes to.
        let appearance = Self.appearance(catalog, of: currentThemeID, wanted: requested ?? systemAppearance.current)
        if let colorScheme {
            if catalog.schemes(for: appearance).contains(where: { $0.id == colorScheme }) {
                switch appearance {
                case .dark: colorSchemeDark = colorScheme
                case .light: colorSchemeLight = colorScheme
                }
            } else {
                Log.settings.error("DEBUG launch arg: unknown AinkradColorScheme '\(colorScheme, privacy: .public)'")
            }
        }
        applyChange(clearingAccent: false)
    }

    /// Re-reads the theme files (a store install or removal) and recomposes, so
    /// the change shows without a restart. Nothing is persisted and the custom
    /// accent is kept; a stored id that is now missing falls back (and is kept).
    public func reloadCatalog() {
        catalog.reload()
        applyChange(clearingAccent: false)
    }

    /// `-AinkradAppearance`: replaces the system appearance while set.
    public private(set) var launchAppearance: ThemeAppearance?

    /// Recomposes after a theme or scheme change; a user change clears the custom accent.
    private func applyChange(clearingAccent: Bool = true) {
        appearance = Self.appearance(catalog, of: currentThemeID, wanted: launchAppearance ?? systemAppearance.current)
        let resolved = Self.resolve(
            catalog: catalog, themeID: currentThemeID, appearance: appearance,
            storedScheme: colorSchemeID(for: appearance))
        if clearingAccent { accentColorHex = nil }
        skin = resolved.skin
        hostSkin = Self.hostSkin(resolved.skin, accentHex: accentColorHex)
        skyProfile = resolved.host.skyProfile
        iconColorFamily = resolved.host.iconColorFamily
        composedKey = resolved.key
        homeLanguage = HomeLanguage.resolve(resolved.host.language).home
        defaultColorSchemeID = resolved.defaultScheme
        variantID = resolved.variantID
        onThemeChange?()
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
        hostSkin = Self.hostSkin(skin, accentHex: hex)
        persist { $0.accentColorHex = hex }
    }

    /// Sets the custom accent from a picked colour; one that can't be
    /// resolved to sRGB clears it.
    public func setAccentColor(_ color: Color) {
        setAccentColorHex(color.hexString)
    }

    private static func hostSkin(_ skin: AinkradSkin, accentHex: String?) -> AinkradSkin {
        var skin = skin
        if let accentHex, let value = UInt32(accentHex.trimmingCharacters(in: ["#"]), radix: 16) {
            skin.palette.accentPrimary = .hex(
                Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255, 1)
        }
        return skin
    }

    // MARK: - Resolution

    private struct Resolved {
        let variantID: String
        let schemeID: String
        let defaultScheme: String
        let skin: AinkradSkin
        let host: HostSkinSection
        var key: String { "\(variantID)|\(schemeID)" }
    }

    /// The variant of `themeID` at `appearance` coloured by the stored scheme.
    /// An unknown theme falls back to Neon and an unknown scheme to the
    /// theme's default; both are logged and neither is written back.
    private static func resolve(
        catalog: ThemeCatalog, themeID: String, appearance: ThemeAppearance, storedScheme: String?
    ) -> Resolved {
        var chosen = variant(catalog, of: themeID, at: appearance)
        if chosen == nil {
            Log.settings.error("Theme \(themeID, privacy: .public) is not installed; using Neon")
            chosen = variant(catalog, of: "neon", at: appearance)
        }
        guard let chosen else {
            Log.settings.error("Neon theme variant is missing; using the standard skin")
            return Resolved(
                variantID: "", schemeID: "", defaultScheme: "", skin: .standard,
                host: HostSkinSection(skyProfile: .neutral, iconColorFamily: .blue))
        }
        var schemeID = storedScheme ?? chosen.language.defaultColorScheme
        var file = catalog.compose(themeVariant: chosen.id, scheme: schemeID)
        if file == nil {
            Log.settings.error("Colour scheme \(schemeID, privacy: .public) is not installed; using the theme default")
            schemeID = chosen.language.defaultColorScheme
            file = catalog.compose(themeVariant: chosen.id, scheme: schemeID)
        }
        let skin = file?.skin ?? catalog.loadedThemes[chosen.id]?.themeFile.skin ?? .standard
        let host =
            file?.host.flatMap { try? JSONDecoder().decode(HostSkinSection.self, from: $0) }
            ?? HostSkinSection(skyProfile: .neutral, iconColorFamily: .blue, language: chosen.language)
        return Resolved(
            variantID: chosen.id, schemeID: schemeID, defaultScheme: chosen.language.defaultColorScheme,
            skin: skin, host: host)
    }

    /// `wanted` when theme `id` (Neon while `id` is not installed) has that
    /// variant, else the other one when it has that.
    private static func appearance(
        _ catalog: ThemeCatalog, of id: String, wanted: ThemeAppearance
    ) -> ThemeAppearance {
        let id = catalog.variants(of: id).isEmpty ? "neon" : id
        if variant(catalog, of: id, at: wanted) != nil { return wanted }
        let other: ThemeAppearance = wanted == .dark ? .light : .dark
        return variant(catalog, of: id, at: other) != nil ? other : wanted
    }

    /// The variant file of theme `id` at `appearance`.
    private static func variant(
        _ catalog: ThemeCatalog, of id: String, at appearance: ThemeAppearance
    ) -> (id: String, language: LanguageSection)? {
        catalog.variants(of: id)
            .compactMap { key, value in value.hostSection?.language.map { (key, $0) } }
            .filter { $0.1.appearance == appearance }
            .min { $0.0 < $1.0 }
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
