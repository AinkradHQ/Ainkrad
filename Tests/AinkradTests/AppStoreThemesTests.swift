import AinkradAppKitContract
import AinkradHostRuntime
import CryptoKit
import Foundation
import Testing

@testable import Ainkrad

/// A store wired like production — a real `AppStoreService` and `ThemeInstaller`
/// over a bootstrapped environment's `ThemeManager` — with a stub catalog and
/// stub downloads.
@MainActor
struct StoreThemeHarness {
    final class Source: CatalogSource {
        var themes: [ThemeCatalogEntry] = []
        func fetchCatalog() async throws -> [CatalogEntry] { [] }
        func fetchCatalogAndThemes() async throws -> (apps: [CatalogEntry], themes: [ThemeCatalogEntry]) {
            ([], themes)
        }
    }
    final class HTTP: HTTPClient {
        var payload: [URL: Data] = [:]
        func get(_ url: URL) async throws -> Data {
            guard let data = payload[url] else { throw HTTPError.status(404) }
            return data
        }
    }

    static let gleam: [String: String] = [
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
    static let ember = [
        "ember-dark.theme": #"""
        {"schemaVersion": 1, "id": "ember.dark", "name": "Ember", "base": "neonBlue",
         "host": {"language": {"id": "ember", "name": "Ember", "appearance": "dark",
                               "defaultColorScheme": "neonBlue", "fontFamily": "exo2"}}}
        """#
    ]
    static let aurora = [
        "aurora-dark.theme": #"""
        {"schemaVersion": 1, "id": "aurora.dark", "name": "Aurora", "base": "neonBlue",
         "host": {"language": {"id": "aurora", "name": "Aurora", "appearance": "dark",
                               "defaultColorScheme": "nord", "fontFamily": "exo2"}}}
        """#
    ]
    static let mint = [
        "mint.scheme": ##"""
        {"schemaVersion": 1, "id": "mint", "name": "Mint", "appearance": "dark",
         "palette": {"background": "#0F1F1A", "accentPrimary": "#3DDC97", "accentSecondary": "#9BF6D4"}}
        """##
    ]

    let env: AppEnvironment
    let cleanup: () -> Void
    let http = HTTP()
    let source = Source()
    let store: AppStoreStore

    init(_ label: String = "store-themes") {
        let t = TestHome.make(label)
        env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        cleanup = t.cleanup
        let persistence = env.persistence
        let themeInstaller = ThemeInstaller(
            http: http,
            storeRoot: t.home.shared(.config).appendingPathComponent("Themes/Store", isDirectory: true),
            persistence: persistence, themeManager: env.themeManager)
        let pluginInstaller = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: URL(fileURLWithPath: "/tmp/p"), pluginDataDir: URL(fileURLWithPath: "/tmp/d"),
            retainedDataDir: URL(fileURLWithPath: "/tmp/r"),
            persistence: persistence, registry: env.registry, loadBundle: { _ in .failure(PluginRejection(reason: "x")) })
        let service = AppStoreService(
            catalog: CatalogService(source: source, persistence: persistence), installer: pluginInstaller,
            mcpInstaller: MCPServerInstaller(
                configStore: MCPServerConfigStore(persistence: persistence, secrets: InMemorySecretStore()),
                persistence: persistence),
            persistence: persistence, themeInstaller: themeInstaller)
        store = AppStoreStore(service: service, registry: env.registry, themeManager: env.themeManager)
        store.tab = .themes
    }

    /// Serves `files` and returns a catalog entry listing them with their digests.
    func entry(
        _ id: String, kind: ThemeCatalogEntry.Kind = .theme, version: String = "1.0.0",
        files: [String: String], description: String = "", author: String? = nil
    ) -> ThemeCatalogEntry {
        let listed = files.keys.sorted().map { name in
            let url = URL(string: "https://e/themes/\(id)/\(version)/\(name)")!
            let data = Data(files[name]!.utf8)
            http.payload[url] = data
            return ThemeCatalogEntry.File(
                url: url, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
        return ThemeCatalogEntry(
            id: id, kind: kind, displayName: id.capitalized, description: description, version: version,
            author: author, format: 1, files: listed, screenshots: nil)
    }

    /// The four Themes-tab states: Aurora available, Gleam installed (with
    /// Apply), Ember with an update, Mint an installed scheme with a swatch.
    func installFixtureStates() async {
        source.themes = [
            entry("aurora", files: Self.aurora, description: "Cool greens over a night sky.", author: "Ainkrad"),
            entry("gleam", files: Self.gleam, description: "Bright and rounded. Light and dark.", author: "Ainkrad"),
            entry("ember", files: Self.ember, description: "Warm chrome for late nights."),
            entry("mint", kind: .colorScheme, files: Self.mint, description: "A fresh green accent."),
        ]
        await store.refresh()
        for id in ["gleam", "ember", "mint"] { await store.install(id) }
        source.themes[2] = entry("ember", version: "1.1.0", files: Self.ember, description: "Warm chrome for late nights.")
        await store.refresh()
    }

    func row(_ id: String) -> AppStoreRow? { store.themeRows.first { $0.id == id } }
}

@Suite("App Store themes tab")
@MainActor
struct AppStoreThemesTests {
    @Test("theme rows: available, installed with Apply, update, scheme with swatch, bundled Neon")
    func rowStates() async throws {
        let h = StoreThemeHarness()
        defer { h.cleanup() }
        await h.installFixtureStates()
        #expect(h.store.themeFailure == nil)

        let aurora = try #require(h.row("aurora"))
        #expect(aurora.status == .available && aurora.kind == .theme)
        #expect(aurora.appearancesText == "1 appearance")
        let gleam = try #require(h.row("gleam"))
        #expect(gleam.status == .installed && gleam.isManaged && !gleam.isApplied)
        #expect(gleam.appearancesText == "Dark · Light")
        let ember = try #require(h.row("ember"))
        #expect(ember.status == .updateAvailable && ember.installedVersion == "1.0.0" && ember.catalogVersion == "1.1.0")
        let mint = try #require(h.row("mint"))
        #expect(mint.kind == .colorScheme && mint.status == .installed && mint.appearancesText == "Dark")
        #expect(mint.swatch.count == 3)
        // Bundled: installed and in use, never removable.
        let neon = try #require(h.row("neon"))
        #expect(neon.status == .installed && !neon.isManaged && neon.isApplied)
        // Installed first, then available; themes never reach the apps list; never a restart.
        #expect(h.store.themeRows.last?.id == "aurora")
        #expect(!h.store.rows.contains { $0.kind.isTheme })
        #expect(h.store.needsRestart.isEmpty)
    }

    @Test("filters and search work on themes")
    func filtersAndSearch() async {
        let h = StoreThemeHarness()
        defer { h.cleanup() }
        await h.installFixtureStates()
        let s = h.store
        #expect(Set(s.visibleRows.map(\.id)) == ["aurora", "gleam", "ember", "mint", "neon"])
        s.filter = .installed
        #expect(Set(s.visibleRows.map(\.id)) == ["gleam", "ember", "mint", "neon"])
        s.filter = .updates
        #expect(s.visibleRows.map(\.id) == ["ember"])
        s.filter = .all
        s.searchQuery = "night"
        #expect(Set(s.visibleRows.map(\.id)) == ["aurora", "ember"])
        s.searchQuery = "ainkrad"  // author
        #expect(Set(s.visibleRows.map(\.id)) == ["aurora", "gleam"])
        s.searchQuery = "zzz"
        #expect(s.visibleRows.isEmpty)
        #expect(s.emptyState.message == "No themes match \"zzz\".")
    }

    @Test("an update replaces the theme; uninstall removes a store theme")
    func updateAndUninstall() async throws {
        let h = StoreThemeHarness()
        defer { h.cleanup() }
        await h.installFixtureStates()
        await h.store.update("ember")
        #expect(h.row("ember")?.status == .installed)
        #expect(h.row("ember")?.installedVersion == "1.1.0")

        h.store.uninstall("gleam")
        #expect(h.row("gleam")?.status == .available)
        #expect(!h.env.themeManager.themes.contains { $0.id == "gleam" })
    }

    @Test("Apply goes through ThemeManager, and an installed theme is in Settings at once")
    func applyAndSettings() async throws {
        let h = StoreThemeHarness()
        defer {
            AinkradFont.configure(scale: 1, family: .exo2)
            h.cleanup()
        }
        await h.installFixtureStates()
        let group = SettingsPath(["workspace", "appearance", "theme"])
        let theme = try #require(HostSettingsCatalog.themeFields(h.env, group: group).first { $0.label == "Theme" })
        guard case .select(let options, _) = theme.kind else {
            Issue.record("Theme is not a select")
            return
        }
        #expect(options.map(\.id).contains("gleam"))

        h.store.apply("gleam")
        #expect(h.env.themeManager.activeThemeID == "gleam")
        #expect(h.row("gleam")?.isApplied == true)
        #expect(h.row("neon")?.isApplied == false)

        h.store.apply("mint")
        #expect(h.env.themeManager.skin.id == "mint")
        #expect(h.row("mint")?.isApplied == true)
    }

    @Test("a refused install shows the installer's problem text and writes nothing")
    func failureShowsProblemText() async throws {
        let h = StoreThemeHarness()
        defer { h.cleanup() }
        var bad = StoreThemeHarness.ember
        bad["ember-dark.theme"] = bad["ember-dark.theme"]!.replacingOccurrences(
            of: #""name": "Ember", "base""#, with: #""name": "Ember", "sparkle": 1, "base""#)
        h.source.themes = [h.entry("ember", files: bad)]
        await h.store.refresh()
        await h.store.install("ember")
        let failure = try #require(h.store.themeFailure)
        #expect(failure.name == "Ember")
        #expect(failure.text.hasPrefix("theme ember.dark: ") && failure.text.contains("sparkle"), "\(failure.text)")
        #expect(h.row("ember")?.status == .available)
        #expect(h.store.error == nil)  // the apps' one-liner stays clear
        #expect(AppStoreStore.themeFailureText(AppStoreError.checksumMismatch) == "Integrity check failed.")
    }

    @Test("More themes… in Settings and the Setup hint both land on the Themes tab")
    func entryPointsLandOnThemes() throws {
        let h = StoreThemeHarness()
        defer { h.cleanup() }
        let env = h.env
        let group = SettingsPath(["workspace", "appearance", "theme"])
        let more = try #require(HostSettingsCatalog.themeFields(env, group: group).first { $0.label == "More themes" })
        guard case .action(let title, let action) = more.kind else {
            Issue.record("not an action")
            return
        }
        #expect(title == "More themes…")

        env.isSettingsPresented = true
        env.appStoreStore.tab = .apps
        action()
        #expect(env.isAppStorePresented && !env.isSettingsPresented && env.appStoreStore.tab == .themes)

        // The Setup appearance step's hint calls the same entry point.
        env.isAppStorePresented = false
        env.appStoreStore.tab = .apps
        env.presentThemeStore()
        #expect(env.isAppStorePresented && env.appStoreStore.tab == .themes)
    }
}
