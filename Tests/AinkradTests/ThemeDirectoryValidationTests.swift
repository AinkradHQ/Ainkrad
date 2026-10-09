import AinkradAppKitUI
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// Validates real theme files (e.g. `AinkradCatalog/themes`) from the directory in
/// `AINKRAD_THEMES_DIR`, set by `make validate-themes THEMES=<dir>` through xcodebuild's
/// `TEST_RUNNER_` prefix. Without it the check prints a loud skip and passes, like
/// `make abi-check` without its toolchain.
///
/// Also tests the host's Glass code paths on a small synthetic language written inline:
/// a mechanism fixture, not Glass's look.
@Suite("Theme directory validation")
@MainActor
struct ThemeDirectoryValidationTests {
    @Test("every theme file in AINKRAD_THEMES_DIR loads, composes and reads")
    func validateThemesDir() {
        guard let raw = ProcessInfo.processInfo.environment["AINKRAD_THEMES_DIR"], !raw.isEmpty else {
            print("SKIPPED: set AINKRAD_THEMES_DIR (make validate-themes THEMES=<dir>) — no theme files were validated")
            return
        }
        let dir = URL(fileURLWithPath: raw, isDirectory: true)
        let problems = ThemeDirectoryValidator.problems(in: dir)
        #expect(problems.isEmpty, "\(dir.path):\n\(problems.joined(separator: "\n"))")
        print("validate-themes: \(dir.path): \(problems.count) problem(s)")
    }

    // MARK: - Synthetic glass-mechanism language

    /// Glass's mechanisms (material, shape language, home keys, system font) on the
    /// bundled base, with readable light and dark schemes.
    static let mechanism: [String: String] = [
        "mech-dark.theme": variant("dark", scheme: "mechDark"),
        "mech-light.theme": variant("light", scheme: "mechLight"),
        "mech-dark.scheme": scheme(
            "mechDark", "dark", background: "#1E1E1E", surface: "#2A2A2C", elevated: "#3A3A3C",
            foreground: "#F5F5F7", status: ("#30D158", "#FFD60A", "#FF453A"), ansi: "#B0B0B5"),
        "mech-light.scheme": scheme(
            "mechLight", "light", background: "#ECECEE", surface: "#F6F6F8", elevated: "#FFFFFF",
            foreground: "#1D1D1F", status: ("#248A3D", "#B25000", "#D70015"), ansi: "#545458"),
    ]

    private static func variant(_ appearance: String, scheme: String) -> String {
        """
        {"schemaVersion": 1, "id": "mech.\(appearance)", "name": "Mechanism", "base": "neonBlue",
         "material": {"kind": "glass", "panelOpacity": 0.5},
         "shape": {"style": "continuous", "corners": "all"},
         "host": {"language": {"id": "mech", "name": "Mechanism", "appearance": "\(appearance)",
                               "defaultColorScheme": "\(scheme)", "fontFamily": "system", "layout": "islands",
                               "sky": false, "islandArt": false, "paneBackdrop": "material", "appTile": "plain"}}}
        """
    }

    private static func scheme(
        _ id: String, _ appearance: String, background: String, surface: String, elevated: String,
        foreground: String, status: (String, String, String), ansi: String
    ) -> String {
        let ansiList = Array(repeating: "\"\(ansi)\"", count: 16).joined(separator: ", ")
        return """
            {"schemaVersion": 1, "id": "\(id)", "name": "\(id)", "appearance": "\(appearance)",
             "palette": {"background": "\(background)", "surface": "\(surface)", "surfaceElevated": "\(elevated)",
                         "foreground": "\(foreground)", "success": "\(status.0)", "warning": "\(status.1)",
                         "danger": "\(status.2)"},
             "terminal": {"background": "\(background)", "foreground": "\(foreground)", "cursor": "\(foreground)",
                          "selection": "\(elevated)", "ansi": [\(ansiList)]},
             "host": {"iconColorFamily": "blue"}}
            """
    }

    @Test("the glass mechanism language loads, composes and resolves Glass's keys")
    func glassMechanism() throws {
        let dir = ThemeFixtures.tempDir(Self.mechanism)
        let catalog = ThemeCatalog(bundle: .main, userRoots: [dir])
        #expect(catalog.issues.isEmpty, "\(catalog.issues)")

        let dark = try #require(catalog.compose(themeVariant: "mech.dark", scheme: "mechDark")).skin
        let light = try #require(catalog.compose(themeVariant: "mech.light", scheme: "mechLight")).skin
        for skin in [dark, light] {
            #expect(skin.material.kind == "glass")
            #expect(skin.shape.style == "continuous")
            // The shape language rewrote the base's chamfer component tokens (read through
            // the encoded skin: component tokens are not public to the host).
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(skin)) as? [String: Any]
            let button = (encoded?["components"] as? [String: Any])?["button"] as? [String: Any]
            #expect((button?["shape"] as? [String: Any])?["style"] as? String == "continuous")
        }
        // A bundled dark scheme composes onto the glass variant too (decision 1).
        #expect(catalog.compose(themeVariant: "mech.dark", scheme: "nord")?.skin.material.kind == "glass")

        let language = try #require(catalog.variants(of: "mech")["mech.light"]?.hostSection?.language)
        #expect(UIFontFamily(rawValue: language.fontFamily) == .system)
        let home = HomeLanguage.resolve(language)
        #expect(home.problems.isEmpty)
        #expect(home.home == HomeLanguage(sky: false, islandArt: false, paneBackdrop: .material, appTile: .plain))

        #expect(ThemeDirectoryValidator.problems(in: dir).isEmpty)
    }

    @Test("the validator reports unreadable colours, broken files and an empty directory")
    func validatorReportsProblems() {
        // Neon's light-on-dark foreground on a light background, and a dark ANSI colour on a dark terminal.
        var files = Self.mechanism
        files["mech-light.scheme"] = #"""
            {"schemaVersion": 1, "id": "mechLight", "name": "Pale", "appearance": "light",
             "palette": {"background": "#F4F4F0", "surface": "#FFFFFF", "surfaceElevated": "#FFFFFF"}}
            """#
        files["mech-dark.scheme"] = Self.scheme(
            "mechDark", "dark", background: "#1E1E1E", surface: "#2A2A2C", elevated: "#3A3A3C",
            foreground: "#F5F5F7", status: ("#30D158", "#FFD60A", "#FF453A"), ansi: "#202022")
        files["broken.theme"] = "{ not json"
        let problems = ThemeDirectoryValidator.problems(in: ThemeFixtures.tempDir(files))
        #expect(problems.contains { $0.hasPrefix("broken.theme") }, "\(problems)")
        #expect(problems.contains { $0.hasPrefix("scheme mechLight: foreground/background") }, "\(problems)")
        #expect(problems.contains { $0.hasPrefix("scheme mechDark: terminal ansi[0]") }, "\(problems)")

        let empty = ThemeDirectoryValidator.problems(in: ThemeFixtures.tempDir([:]))
        #expect(empty.contains { $0.contains("no .theme or .scheme files") }, "\(empty)")
    }
}

/// Every problem with the theme and scheme files under one directory; empty = valid.
@MainActor
enum ThemeDirectoryValidator {
    /// WCAG AA for body text, and 3:1 for status glyphs, badges and ANSI colours
    /// (the `SignalContrastTests` bar).
    static let textRatio = 4.5
    static let glyphRatio = 3.0

    static func problems(in dir: URL) -> [String] {
        var problems: [String] = []
        let bundled = ThemeCatalog(bundle: .main)
        let catalog = ThemeCatalog(bundle: .main, userRoots: [dir])
        // Warnings count: a theme published for this host must load without fallbacks.
        problems += catalog.issues.map(\.description)

        let variantIDs = Set(catalog.loadedThemes.keys).subtracting(bundled.loadedThemes.keys).sorted()
        let allSchemes = ThemeAppearance.allCases.flatMap { catalog.schemes(for: $0) }
        let bundledSchemeIDs = Set(ThemeAppearance.allCases.flatMap { bundled.schemes(for: $0) }.map(\.id))
        let schemes = allSchemes.filter { !bundledSchemeIDs.contains($0.id) }.sorted { $0.id < $1.id }
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { ["theme", "scheme"].contains($0.pathExtension) } ?? []
        if files.isEmpty { problems.append("\(dir.path): no .theme or .scheme files") }

        // Each theme × its default scheme, and a dark theme × every bundled dark scheme.
        for id in variantIDs {
            guard let language = catalog.loadedThemes[id]?.hostSection?.language else {
                problems.append("theme \(id): no host.language (a base skin cannot be published)")
                continue
            }
            var schemeIDs = [language.defaultColorScheme]
            if language.appearance == .dark { schemeIDs += neonSchemeIDs }
            for schemeID in schemeIDs where catalog.compose(themeVariant: id, scheme: schemeID) == nil {
                problems.append("theme \(id): does not compose with \(schemeID)")
            }
        }

        // The store's install checks (identity binding, bundled base), per folder of theme files.
        // The entry id is the folder's language id (its first theme file's), else the folder name.
        let themeFiles = files.filter { $0.pathExtension == "theme" }
        for folder in Set(themeFiles.map { $0.deletingLastPathComponent() }) {
            let languageID = themeFiles.filter { $0.deletingLastPathComponent() == folder }.sorted { $0.path < $1.path }
                .lazy.compactMap { url -> String? in
                    let dict = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
                    return (((dict as? [String: Any])?["host"] as? [String: Any])?["language"] as? [String: Any])?["id"]
                        as? String
                }.first
            problems += bundled.trialProblems(
                entryID: languageID ?? folder.lastPathComponent, isTheme: true, staged: folder
            ).map { "\(folder.lastPathComponent)/: \($0)" }
        }

        for scheme in schemes {
            let variantID =
                variantIDs.first { catalog.loadedThemes[$0]?.hostSection?.language?.defaultColorScheme == scheme.id }
                ?? variantIDs.first { catalog.loadedThemes[$0]?.hostSection?.language?.appearance == scheme.appearance }
                ?? (scheme.appearance == .dark ? "neon.dark" : nil)
            guard let variantID, let skin = catalog.compose(themeVariant: variantID, scheme: scheme.id)?.skin else {
                problems.append("scheme \(scheme.id): no theme of its appearance to compose with")
                continue
            }
            problems += contrastProblems(skin).map { "scheme \(scheme.id): \($0)" }
        }
        return problems
    }

    private static func contrastProblems(_ skin: AinkradSkin) -> [String] {
        var problems: [String] = []
        func check(_ name: String, _ a: AinkradColorToken, _ b: AinkradColorToken, _ minimum: Double) {
            let ratio = skin.color(a).contrastRatio(against: skin.color(b))
            if ratio < minimum { problems.append("\(name) is \(String(format: "%.2f", ratio)), needs \(minimum)") }
        }
        let palette = skin.palette
        for (name, surface) in [("background", palette.background), ("surface", palette.surface),
                                ("surfaceElevated", palette.surfaceElevated)] {
            check("foreground/\(name)", palette.foreground, surface, textRatio)
        }
        // `SignalContrastTests`: each status colour on the panel and hover surfaces, and the
        // launcher badge (background drawn on the status colour).
        for (name, status) in [("success", palette.success), ("warning", palette.warning),
                               ("danger", palette.danger), ("foreground", palette.foreground)] {
            check("\(name)/surface", status, palette.surface, glyphRatio)
            check("\(name)/surfaceElevated", status, palette.surfaceElevated, glyphRatio)
            check("badge background/\(name)", palette.background, status, glyphRatio)
        }
        let terminal = skin.terminal
        check("terminal foreground/background", terminal.foreground, terminal.background, textRatio)
        for (index, colour) in terminal.ansi.enumerated() {
            check("terminal ansi[\(index)]/background", colour, terminal.background, glyphRatio)
        }
        return problems
    }
}
