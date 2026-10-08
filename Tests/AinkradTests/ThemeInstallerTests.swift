import AinkradHostRuntime
import CryptoKit
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("ThemeInstaller")
@MainActor
struct ThemeInstallerTests {
    private final class StubHTTP: HTTPClient {
        var payload: [URL: Data] = [:]
        var calls = 0
        func get(_ url: URL) async throws -> Data {
            calls += 1
            guard let data = payload[url] else { throw HTTPError.status(404) }
            return data
        }
    }

    /// `gleam`: a dark and a light variant, each naming its own carried scheme.
    private static let gleam: [String: String] = [
        "gleam-dark.theme": #"""
        {"schemaVersion": 1, "id": "gleam.dark", "name": "Gleam", "base": "neonBlue",
         "host": {"language": {"id": "gleam", "name": "Gleam", "appearance": "dark",
                               "defaultColorScheme": "gleam-dark", "fontFamily": "system"}}}
        """#,
        "gleam-light.theme": #"""
        {"schemaVersion": 1, "id": "gleam.light", "name": "Gleam", "base": "neonBlue",
         "host": {"language": {"id": "gleam", "name": "Gleam", "appearance": "light",
                               "defaultColorScheme": "gleam-light", "fontFamily": "system"}}}
        """#,
        "gleam-dark.scheme": #"""
        {"schemaVersion": 1, "id": "gleam-dark", "name": "Gleam Dark", "appearance": "dark",
         "palette": {"background": "#101418"}}
        """#,
        "gleam-light.scheme": #"""
        {"schemaVersion": 1, "id": "gleam-light", "name": "Gleam Light", "appearance": "light",
         "palette": {"background": "#F4F6F8"}}
        """#,
    ]
    private static let mint = [
        "mint.scheme": ##"{"schemaVersion": 1, "id": "mint", "name": "Mint", "appearance": "dark", "palette": {"background": "#0F1F1A"}}"##
    ]

    private struct Harness {
        let http = StubHTTP()
        let themesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-installer-\(UUID().uuidString)", isDirectory: true)
        let persistence = InMemoryPersistenceStore()
        var storeRoot: URL { themesRoot.appendingPathComponent("Store", isDirectory: true) }

        @MainActor
        func make(settings: GlobalSettings? = nil) -> (ThemeInstaller, ThemeManager) {
            if let settings { persistence.save(settings) }
            let manager = ThemeManager(
                persistence: persistence, catalog: ThemeCatalog(bundle: .main, userRoots: [themesRoot]))
            let installer = ThemeInstaller(
                http: http, storeRoot: storeRoot, persistence: persistence, themeManager: manager)
            return (installer, manager)
        }

        /// Serves `files` and returns an entry listing them with their real digests.
        func entry(
            _ id: String, kind: ThemeCatalogEntry.Kind = .theme, version: String = "1.0.0",
            files: [String: String], badSHA: Bool = false
        ) -> ThemeCatalogEntry {
            let listed = files.keys.sorted().map { name in
                let url = URL(string: "https://e/themes/\(id)/\(name)")!
                let data = Data(files[name]!.utf8)
                http.payload[url] = data
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return ThemeCatalogEntry.File(url: url, sha256: badSHA ? String(sha.reversed()) : sha)
            }
            return ThemeCatalogEntry(
                id: id, kind: kind, displayName: id, description: "", version: version, author: nil, format: 1,
                files: listed, screenshots: nil)
        }

        func installedFiles(_ id: String) -> Set<String> {
            let dir = storeRoot.appendingPathComponent(id)
            return Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        }

        /// Nothing in the store folder and nothing recorded.
        func wroteNothing() -> Bool {
            ((try? FileManager.default.contentsOfDirectory(atPath: storeRoot.path)) ?? []).isEmpty
                && persistence.load(InstalledThemesDocument.self) == nil
        }
    }

    private func invalidText(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch AppStoreError.invalidBundle(let text) { return text } catch { return "\(error)" }
        return nil
    }

    @Test("a theme carrying its 2 default schemes installs all 4 files, loads live, and removes all 4")
    func themeWithSchemesInstallsAndRemoves() async throws {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        // The stored theme is not installed yet: Neon shows meanwhile.
        let (installer, manager) = h.make(settings: GlobalSettings(theme: "gleam"))
        manager.setAccentColorHex("FF00AA")
        #expect(manager.skin.id == "neonBlue")

        try await installer.install(h.entry("gleam", files: Self.gleam))
        #expect(h.installedFiles("gleam") == Set(Self.gleam.keys))
        let record = try #require(h.persistence.load(InstalledThemesDocument.self)?.installed["gleam"])
        #expect(record == .init(version: "1.0.0", kind: .theme, files: Self.gleam.keys.sorted()))
        // Live, no restart: the stored theme now resolves, and the custom accent survives the reload.
        #expect(manager.themes.contains { $0.id == "gleam" })
        #expect(manager.skin.id == "gleam-dark")
        #expect(manager.accentColorHex == "FF00AA")
        #expect(manager.colorSchemes(for: .light).map(\.id) == ["gleam-light"])

        try installer.uninstall(id: "gleam")
        #expect(!FileManager.default.fileExists(atPath: h.storeRoot.appendingPathComponent("gleam").path))
        #expect(h.persistence.load(InstalledThemesDocument.self)?.installed["gleam"] == nil)
        #expect(manager.skin.id == "neonBlue")
        #expect(manager.activeThemeID == "neon")
        #expect(manager.currentThemeID == "gleam")  // kept, so a reinstall restores it
        #expect(h.persistence.load(GlobalSettings.self)?.theme == "gleam")
    }

    @Test("an update replaces the installed files")
    func updateReplacesFiles() async throws {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        try await installer.install(h.entry("gleam", files: Self.gleam))

        var darkOnly = Self.gleam.filter { $0.key.contains("dark") }
        darkOnly["gleam-dark.scheme"] = darkOnly["gleam-dark.scheme"]!.replacingOccurrences(of: "101418", with: "202428")
        try await installer.install(h.entry("gleam", version: "1.1.0", files: darkOnly))
        #expect(h.installedFiles("gleam") == ["gleam-dark.theme", "gleam-dark.scheme"])
        let scheme = try String(
            contentsOf: h.storeRoot.appendingPathComponent("gleam/gleam-dark.scheme"), encoding: .utf8)
        #expect(scheme.contains("202428"))
        #expect(h.persistence.load(InstalledThemesDocument.self)?.installed["gleam"]?.version == "1.1.0")
        #expect(
            ((try? FileManager.default.contentsOfDirectory(atPath: h.storeRoot.path)) ?? []) == ["gleam"],
            "no staging folder is left behind")
    }

    @Test("a standalone colour scheme installs and removes; removing the active one falls back to the theme default")
    func standaloneSchemeAndActiveRemoval() async throws {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, manager) = h.make()
        try await installer.install(h.entry("mint", kind: .colorScheme, files: Self.mint))
        #expect(h.installedFiles("mint") == ["mint.scheme"])
        #expect(manager.colorSchemes.contains { $0.id == "mint" })

        manager.setColorScheme("mint", for: .dark)
        manager.setAccentColorHex("00FF00")
        #expect(manager.skin.id == "mint")

        try installer.uninstall(id: "mint")
        #expect(h.installedFiles("mint").isEmpty)
        #expect(!manager.colorSchemes.contains { $0.id == "mint" })
        #expect(manager.skin.id == "neonBlue")
        #expect(manager.colorSchemeID(for: .dark) == "mint")  // stored id kept
        #expect(manager.accentColorHex == "00FF00")
    }

    @Test("a theme carrying a scheme its variants do not name is refused")
    func undeclaredSchemeRefused() async {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        var files = Self.gleam
        files["stray.scheme"] = #"{"schemaVersion": 1, "id": "stray", "appearance": "dark", "palette": {}}"#
        let text = await invalidText { try await installer.install(h.entry("gleam", files: files)) }
        #expect(text == "scheme stray: not a default colour scheme of gleam")
        #expect(h.wroteNothing())
    }

    @Test("a bad sha256 writes nothing")
    func badChecksumWritesNothing() async {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        await #expect(throws: AppStoreError.checksumMismatch) {
            try await installer.install(h.entry("gleam", files: Self.gleam, badSHA: true))
        }
        #expect(h.wroteNothing())
    }

    @Test("an id mismatch writes nothing, for a theme and for a scheme entry")
    func idMismatchWritesNothing() async {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        var files = Self.gleam
        files["gleam-dark.theme"] = files["gleam-dark.theme"]!.replacingOccurrences(
            of: #""id": "gleam", "#, with: #""id": "other", "#)
        let text = await invalidText { try await installer.install(h.entry("gleam", files: files)) }
        // The orphaned scheme is reported too; the binding failure leads.
        #expect(text?.split(separator: "\n").first == "theme gleam.dark: host.language.id must be gleam", "\(text ?? "nil")")

        let scheme = await invalidText {
            try await installer.install(h.entry("spearmint", kind: .colorScheme, files: Self.mint))
        }
        #expect(scheme == "scheme mint: id must be spearmint")
        #expect(h.wroteNothing())
    }

    @Test("a file with an unknown key writes nothing and reports the issue")
    func unknownKeyWritesNothing() async throws {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        var files = Self.gleam
        files["gleam-dark.theme"] = files["gleam-dark.theme"]!.replacingOccurrences(
            of: #""name": "Gleam", "base""#, with: #""name": "Gleam", "sparkle": 1, "base""#)
        let text = try #require(await invalidText { try await installer.install(h.entry("gleam", files: files)) })
        #expect(text.hasPrefix("theme gleam.dark: "), "\(text)")
        #expect(text.contains("sparkle"), "\(text)")
        #expect(h.wroteNothing())
    }

    @Test("a store theme may base only on a bundled base skin")
    func nonBaseSkinBaseRefused() async {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        var files = Self.gleam
        files["gleam-dark.theme"] = files["gleam-dark.theme"]!.replacingOccurrences(
            of: #""base": "neonBlue""#, with: #""base": "neon.dark""#)
        let text = await invalidText { try await installer.install(h.entry("gleam", files: files)) }
        #expect(text?.hasPrefix("theme gleam.dark: unknownBase neon.dark") == true, "\(text ?? "nil")")
        #expect(h.wroteNothing())
    }

    @Test("a traversal id is refused before any download or filesystem call")
    func traversalIDRefused() async {
        let h = Harness()
        defer { try? FileManager.default.removeItem(at: h.themesRoot) }
        let (installer, _) = h.make()
        let text = await invalidText { try await installer.install(h.entry("../x", files: Self.mint)) }
        #expect(text == "unsafe theme id ../x")
        #expect(throws: AppStoreError.invalidBundle("unsafe theme id ../x")) { try installer.uninstall(id: "../x") }
        #expect(h.http.calls == 0)
        #expect(!FileManager.default.fileExists(atPath: h.themesRoot.path))
    }
}
