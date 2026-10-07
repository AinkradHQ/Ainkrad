import AinkradAppKitUI
import Foundation

/// Loads theme files from the main bundle via `ainkradLoadThemes` and provides theme file resolution.
final class ThemeCatalog: Sendable {
    static let shared = ThemeCatalog()

    struct LoadedTheme: Sendable {
        let themeFile: AinkradThemeFile
        let hostSection: HostSkinSection?
    }

    let loadedThemes: [String: LoadedTheme]
    let issues: [AinkradThemeIssue]

    init(bundle: Bundle = .main) {
        let themeURLs =
            (bundle.urls(forResourcesWithExtension: "theme", subdirectory: "Themes") ?? [])
            + (bundle.urls(forResourcesWithExtension: "theme", subdirectory: nil) ?? [])

        // Unique by path
        let uniqueURLs = Array(Set(themeURLs))
        let filesData = uniqueURLs.compactMap { try? Data(contentsOf: $0) }

        let result = ainkradLoadThemes(filesData)
        self.issues = result.issues

        for issue in result.issues {
            Log.settings.error("Theme catalog load issue: \(issue.description, privacy: .public)")
        }

        var themesDict: [String: LoadedTheme] = [:]
        for (id, file) in result.themes {
            var section: HostSkinSection?
            if let hostData = file.host {
                do {
                    section = try JSONDecoder().decode(HostSkinSection.self, from: hostData)
                } catch {
                    Log.settings.error(
                        "Failed to decode host section for theme '\(id, privacy: .public)': \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            themesDict[id] = LoadedTheme(themeFile: file, hostSection: section)
        }
        self.loadedThemes = themesDict
    }

    func themeFile(for themeID: String) -> AinkradThemeFile {
        if let loaded = loadedThemes[themeID] {
            return loaded.themeFile
        }
        if let baseId = fallbackBaseId(for: themeID), let baseLoaded = loadedThemes[baseId] {
            return baseLoaded.themeFile
        }
        return AinkradThemeFile(skin: .standard)
    }

    func hostSection(for themeID: String) -> HostSkinSection? {
        if let loaded = loadedThemes[themeID], let section = loaded.hostSection {
            return section
        }
        if let baseId = fallbackBaseId(for: themeID), let baseLoaded = loadedThemes[baseId],
            let section = baseLoaded.hostSection
        {
            return section
        }
        return nil
    }

    private func fallbackBaseId(for themeID: String) -> String? {
        switch themeID {
        case "cyberPurple", "dracula", "nord", "tokyoNight", "gruvbox", "solarizedDark":
            return "neonBlue"
        default:
            return nil
        }
    }
}
