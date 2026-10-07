import AinkradAppKitContract
import Testing

@testable import Ainkrad

@Suite("Settings search index")
@MainActor
struct SettingsSearchIndexTests {
    private var index: SettingsCatalogIndex {
        SettingsCatalogIndex(catalog: HostSettingsCatalog.build(environment: .preview()))
    }

    @Test("COVERAGE GUARD: every field in the catalog is indexed")
    func everyFieldIsIndexed() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let indexed = SettingsCatalogIndex(catalog: catalog).indexedPaths
        for field in catalog.allFields {
            #expect(
                indexed.contains(field.path),
                "\(field.path) is in the catalog but not the search index")
        }
    }

    @Test("an exact label match outranks a help-text match")
    func exactBeatsHelp() {
        // "Model" is the exact label of the Model & Connections model-picker
        // field; "model" also appears only in the MCP servers field's help
        // text ("Model Context Protocol servers..."), never in its label or
        // keywords — a genuine exact-vs-help-text pair to rank against.
        // (A plain "blur" query does not exercise this: every enabled
        // built-in app contributes its own field labelled exactly "Blur",
        // so every hit ties at the exact-match tier and there is no
        // lower-ranked entry to compare against.)
        let results = index.search("model", currentPage: nil)
        #expect(!results.isEmpty)
        #expect(results[0].label.lowercased() == "model")
        #expect(results[0].score > results.last!.score)
    }

    @Test("keywords find fields whose label does not contain the query")
    func keywordsResolveSynonyms() {
        #expect(!index.search("hotkey", currentPage: nil).isEmpty)
        #expect(!index.search("api key", currentPage: nil).isEmpty)
        #expect(!index.search("dark mode", currentPage: nil).isEmpty)
    }

    @Test("page and group titles are searchable so 'tools mcp' finds the MCP servers field")
    func breadcrumbTextIsSearchable() {
        let results = index.search("tools mcp", currentPage: nil)
        #expect(!results.isEmpty)
    }

    @Test("results carry a breadcrumb naming the page and group")
    func resultsHaveBreadcrumbs() {
        let result = index.search("launcher layout", currentPage: nil).first
        #expect(result?.breadcrumb.contains("›") == true)
    }

    @Test("a match on the current page gets a rank boost")
    func currentPageBoost() {
        let page = HostSettingsCatalog.build(environment: .preview()).pages(in: .workspace)[0]
        let cold = index.search("launcher", currentPage: nil).first!
        let warm = index.search("launcher", currentPage: page.path).first!
        #expect(warm.score > cold.score)
    }

    @Test("an unmatched query returns nothing rather than noise")
    func noResults() {
        #expect(index.search("zzzzqqqq", currentPage: nil).isEmpty)
    }

    @Test("filter matching returns the paths to keep lit on a page")
    func filterMatching() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let page = catalog.pages(in: .workspace)[0]
        let matched = SettingsCatalogIndex(catalog: catalog).matchedPaths("launcher", on: page)
        #expect(matched.count >= 1)
        #expect(matched.count < page.allFields.count)
    }

    // No page builder currently declares a `.secure` field directly (API
    // keys are wrapped behind `.custom` connection panes today), so this
    // pins the guarantee with a synthetic field rather than depending on
    // live catalog data that could vanish without this test noticing.
    @Test("SECURITY: a .secure field never leaks its value into a search result")
    func secureFieldsNeverExposeValue() {
        let path = SettingsPath(["test", "secret"])
        let secretField = SettingsField(
            path: path,
            label: "OpenAI API Key",
            help: "Your OpenAI API key.",
            keywords: ["token", "credential"],
            kind: .secure(.constant("sk-super-secret-value")))
        let page = SettingsPage(
            path: SettingsPath(["test"]),
            title: "Test", icon: "gearshape", group: .workspace, order: 0,
            groups: [
                SettingsGroup(
                    path: SettingsPath(["test", "group"]), title: "Secrets",
                    fields: [secretField])
            ])
        let catalog = SettingsCatalog(pages: [page])
        let searchIndex = SettingsCatalogIndex(catalog: catalog)

        let results = searchIndex.search("OpenAI API Key", currentPage: nil)
        let hit = results.first { $0.path == path }
        #expect(hit != nil, "expected the secure field's own label to find it")
        #expect(
            hit?.valueDescription == nil,
            "a .secure field must never surface its value in a search result")
    }
}
