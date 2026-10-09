/// The user's app-icon COLOR setting. `.auto` follows the current theme.
/// Persisted as `GlobalSettings.appIconChoice` (v1 `blue`/`purple` still decode).
public enum AppIconChoice: String, Codable, CaseIterable, Sendable { case auto, blue, purple }

/// The user's app-icon APPEARANCE setting. `.system` follows the Dock's
/// light/dark; `.light`/`.dark` pin one variant.
public enum AppIconAppearance: String, Codable, CaseIterable, Sendable { case system, light, dark }

/// A concrete resolved icon color family (never `.auto`). Its rawValue is the
/// resource-name prefix (`blue`/`purple`).
public enum AppIconColor: String, CaseIterable, Codable, Sendable { case blue, purple }

/// Pure mapping from the user's settings + the theme's icon family + current system appearance to
/// the bundled composed `.icns` resource base-name. AppKit-free and unit-tested.
public enum AppIconResolver {
    public static func color(for choice: AppIconChoice, themeFamily: AppIconColor) -> AppIconColor {
        switch choice {
        case .auto: return themeFamily
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    public static func isDark(_ appearance: AppIconAppearance, systemDark: Bool) -> Bool {
        switch appearance {
        case .system: return systemDark
        case .light: return false
        case .dark: return true
        }
    }

    public static func resourceName(
        for choice: AppIconChoice, themeFamily: AppIconColor,
        appearance: AppIconAppearance, systemDark: Bool
    ) -> String {
        let family = color(for: choice, themeFamily: themeFamily).rawValue
        return "\(family)-\(isDark(appearance, systemDark: systemDark) ? "dark" : "light")"
    }
}
