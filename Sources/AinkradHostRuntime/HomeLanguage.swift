import Foundation

/// The home surface's structure. One case today; Metro adds `tileGrid`, and
/// every `switch` on it has no `default:` so the new case cannot be missed.
public enum HomeLayoutKind: String, Sendable {
    case islands
}

/// What sits behind a pane: today's blurred render of the sky and islands, the
/// theme's real material (`AinkradMaterialBackground`), or the theme's solid
/// background (panes are content, and Liquid Glass stays out of the content layer).
public enum PaneBackdropKind: String, Sendable {
    case sky
    case material
    case solid
}

/// What floats on the empty home: Neon's painted island, the all-glass island
/// (Liquid Glass), or the plain brand mark.
public enum IslandKind: String, Sendable {
    case art
    case glass
    case mark
}

/// The app tile: Neon's bloom tile, or a calm symbol-on-fill tile.
public enum AppTileKind: String, Sendable {
    case neon
    case plain
}

/// The home keys of a theme's `host.language`, resolved: a missing key takes
/// the Neon value, and an unknown value falls back to it with a problem the
/// catalog lists as a warning (the theme still loads).
public struct HomeLanguage: Equatable, Sendable {
    public var layout: HomeLayoutKind
    public var sky: Bool
    public var island: IslandKind
    public var paneBackdrop: PaneBackdropKind
    public var appTile: AppTileKind
    /// Whether the whole window is see-through glass (the desktop shows
    /// behind the content). Off by default: per Apple's Liquid Glass guidance
    /// the content layer, app background included, stays opaque.
    public var windowGlass: Bool

    public init(
        layout: HomeLayoutKind = .islands, sky: Bool = true, islandArt: Bool = true,
        paneBackdrop: PaneBackdropKind = .sky, appTile: AppTileKind = .neon, windowGlass: Bool = false,
        island: IslandKind? = nil
    ) {
        self.layout = layout
        self.sky = sky
        self.island = island ?? (islandArt ? .art : .mark)
        self.paneBackdrop = paneBackdrop
        self.appTile = appTile
        self.windowGlass = windowGlass
    }

    /// Whether the home shows Neon's painted island.
    public var islandArt: Bool { island == .art }

    /// Today's look.
    public static let neon = HomeLanguage()

    /// Resolves `language`'s raw keys; `problems` holds one line per fallback.
    static func resolve(_ language: LanguageSection?) -> (home: HomeLanguage, problems: [String]) {
        var home = HomeLanguage()
        var problems: [String] = []
        guard let language else { return (home, problems) }
        func pick<T: RawRepresentable>(_ key: String, _ raw: String?, _ fallback: T) -> T where T.RawValue == String {
            guard let raw else { return fallback }
            if let value = T(rawValue: raw) { return value }
            problems.append("\(key) '\(raw)' is unknown; using '\(fallback.rawValue)'")
            return fallback
        }
        home.layout = pick("layout", language.layout, home.layout)
        home.sky = language.sky ?? home.sky
        // `island` wins; a file without it (or a host before it) reads `islandArt`.
        let legacy: IslandKind = (language.islandArt ?? true) ? .art : .mark
        home.island = pick("island", language.island, legacy)
        home.paneBackdrop = pick("paneBackdrop", language.paneBackdrop, home.paneBackdrop)
        home.appTile = pick("appTile", language.appTile, home.appTile)
        home.windowGlass = language.windowGlass ?? home.windowGlass
        if home.paneBackdrop == .sky && !home.sky {
            problems.append("paneBackdrop 'sky' needs sky: true; using 'material'")
            home.paneBackdrop = .material
        }
        return (home, problems)
    }
}
