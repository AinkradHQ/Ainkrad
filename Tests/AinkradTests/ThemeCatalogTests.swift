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

    @Test("the first user root wins an id collision")
    func firstRootWins() throws {
        let first = try fixtureRoot()
        let second = try fixtureRoot()
        let catalog = ThemeCatalog(bundle: .main, userRoots: [first, second])
        #expect(catalog.issues.contains { $0.message.contains("already provided by \(first.path)") })
    }
}
