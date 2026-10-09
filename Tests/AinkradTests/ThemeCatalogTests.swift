import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("ThemeCatalog")
@MainActor
struct ThemeCatalogTests {
    /// A user folder holding one valid variant, one valid scheme and four broken files.
    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-catalog-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Store/test", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let files: [String: String] = [
            "Store/test/test-dark.theme": """
            {"schemaVersion": 1, "id": "test.dark", "name": "Test", "base": "neonBlue",
             "host": {"language": {"id": "test", "name": "Test", "appearance": "dark",
                                   "defaultColorScheme": "testScheme"}}}
            """,
            "Store/test/test.scheme": """
            {"schemaVersion": 1, "id": "testScheme", "name": "Test Scheme", "appearance": "dark",
             "palette": {"background": "#101010"}, "host": {"iconColorFamily": "purple"}}
            """,
            "broken.theme": "{ not json",
            "orphan.theme": #"{"schemaVersion": 1, "id": "orphan", "base": "nope"}"#,
            "neon-copy.theme": #"{"schemaVersion": 1, "id": "neonBlue", "name": "Fake", "base": "neonBlue"}"#,
            "shapey.scheme": #"{"id": "shapey", "appearance": "dark", "shape": {"style": "rounded"}}"#,
            ".hidden.theme": "{ hidden files are skipped",
        ]
        for (path, body) in files {
            try body.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("the bundle loads the base skin, the Neon variant and seven schemes, with no issues")
    func bundleLoadsUnchanged() {
        let catalog = ThemeCatalog(bundle: .main)
        #expect(catalog.issues.isEmpty, "\(catalog.issues)")
        #expect(Set(catalog.loadedThemes.keys) == ["neonBlue", "neon.dark"])
        #expect(catalog.languages.map(\.id) == ["neon"])
        #expect(Set(catalog.schemes(for: .dark).map(\.id)) == Set(neonSchemeIDs))
    }

    @Test("broken, unknown-base, shadowing and language-keyed files become issues, not traps")
    func brokenFilesBecomeIssues() throws {
        let catalog = ThemeCatalog(bundle: .main, userRoots: [try fixtureRoot()])
        #expect(catalog.issues.count == 4, "\(catalog.issues)")
        #expect(catalog.issues.contains { $0.subject == "broken.theme" })
        #expect(catalog.issues.contains { $0.subject == "theme orphan" })
        #expect(catalog.issues.contains { $0.subject == "neon-copy.theme" })
        #expect(catalog.issues.contains { $0.message == "key shape is not allowed in a colour scheme" })
        // The shadowing file did not replace the bundled base skin.
        #expect(catalog.loadedThemes["neonBlue"]?.themeFile.skin.name != "Fake")
    }

    @Test("an AppKit warning stays listed, labelled, next to a theme that loaded")
    func warningIsNotAFailure() throws {
        let catalog = ThemeCatalog(bundle: .main, userRoots: [ThemeFixtures.tempDir(ThemeFixtures.warned)])
        #expect(catalog.loadedThemes["warned"] != nil)
        let issue = try #require(catalog.issues.first { $0.subject == "theme warned" })
        #expect(catalog.issues.count == 1, "\(catalog.issues)")
        #expect(issue.isWarning)
        #expect(issue.description.hasPrefix("theme warned: warning: "))
    }

    @Test("a variant and a scheme compose into the scheme's id with merged host keys")
    func composeVariantAndScheme() throws {
        let catalog = ThemeCatalog(bundle: .main, userRoots: [try fixtureRoot()])
        #expect(catalog.languages.map(\.id) == ["neon", "test"])
        #expect(Array(catalog.variants(of: "test").keys) == ["test.dark"])
        #expect(catalog.schemes(for: .dark).contains { $0.id == "testScheme" })
        #expect(catalog.schemes(for: .light).isEmpty)

        let file = try #require(catalog.compose(themeVariant: "test.dark", scheme: "testScheme"))
        #expect(file.skin.id == "testScheme")
        let host = try JSONDecoder().decode(HostSkinSection.self, from: try #require(file.host))
        #expect(host.language?.id == "test")
        #expect(host.language?.fontFamily == "exo2")
        #expect(host.iconColorFamily == .purple)
        #expect(catalog.compose(themeVariant: "nord", scheme: "testScheme") == nil)
        #expect(catalog.compose(themeVariant: "test.dark", scheme: "missing") == nil)
    }

    @Test("reload picks up a file added after init")
    func reloadSeesNewFiles() throws {
        let root = try fixtureRoot()
        let catalog = ThemeCatalog(bundle: .main, userRoots: [root])
        try ##"{"id": "late", "name": "Late", "appearance": "dark", "palette": {"background": "#202020"}}"##
            .write(to: root.appendingPathComponent("late.scheme"), atomically: true, encoding: .utf8)
        #expect(!catalog.schemes(for: .dark).contains { $0.id == "late" })
        catalog.reload()
        #expect(catalog.schemes(for: .dark).contains { $0.id == "late" })
    }

    @Test("a Debug themes dir ahead of Home loads its files and a Home copy of an id becomes an issue")
    func themesDirAheadOfHome() throws {
        let themesDir = try fixtureRoot()
        let home = try fixtureRoot()
        let catalog = ThemeCatalog(bundle: .main, userRoots: [themesDir, home])
        #expect(catalog.variants(of: "test").keys.contains("test.dark"))
        #expect(catalog.issues.contains { $0.message.contains("already provided by \(themesDir.path)") })
    }

    @Test("home keys: Neon by default, unknown values and sky-less sky backdrops fall back with one warning each")
    func homeLanguageKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = [
            "grid-dark.theme": #"""
            {"schemaVersion": 1, "id": "grid.dark", "base": "neonBlue",
             "host": {"language": {"id": "grid", "layout": "tileGrid", "appTile": "plain"}}}
            """#,
            "bare-dark.theme": #"""
            {"schemaVersion": 1, "id": "bare.dark", "base": "neonBlue",
             "host": {"language": {"id": "bare", "sky": false, "islandArt": false, "paneBackdrop": "sky"}}}
            """#,
        ]
        for (name, body) in files {
            try body.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let catalog = ThemeCatalog(bundle: .main, userRoots: [root])
        func home(_ id: String) -> HomeLanguage {
            HomeLanguage.resolve(catalog.loadedThemes[id]?.hostSection?.language).home
        }

        #expect(home("neon.dark") == .neon)
        #expect(home("grid.dark") == HomeLanguage(appTile: .plain))
        #expect(home("bare.dark") == HomeLanguage(sky: false, islandArt: false, paneBackdrop: .material))
        let warnings = catalog.issues.filter(\.isWarning)
        #expect(warnings.count == 2, "\(catalog.issues)")
        #expect(warnings.contains { $0.subject == "theme grid.dark" && $0.message.hasPrefix("layout 'tileGrid'") })
        #expect(warnings.contains { $0.subject == "theme bare.dark" && $0.message.hasPrefix("paneBackdrop 'sky'") })
        #expect(catalog.languages.contains { $0.id == "grid" })
    }

    @Test("the first user root wins an id collision")
    func firstRootWins() throws {
        let first = try fixtureRoot()
        let second = try fixtureRoot()
        let catalog = ThemeCatalog(bundle: .main, userRoots: [first, second])
        #expect(catalog.issues.contains { $0.message.contains("already provided by \(first.path)") })
    }
}
