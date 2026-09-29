import Testing
@testable import Ainkrad
import AinkradAppKitContract

/// The information-architecture invariant for Settings: everything is at most
/// two levels deep, and every section that used to live behind the Sage's
/// pill bar has a home among the INTELLIGENCE pages.
@Suite("Settings information architecture")
@MainActor
struct SettingsIATests {
    private var catalog: SettingsCatalog { HostSettingsCatalog.build(environment: .preview()) }

    @Test("the INTELLIGENCE group holds the six agent pages in order")
    func intelligencePages() {
        #expect(catalog.pages(in: .intelligence).map(\.title) == [
            "Model & Connections",
            "Permissions & Sandbox",
            "Memory",
            "Skills",
            "Tools",
            "Privacy & Data"
        ])
    }

    @Test("every former Sage tab section has a home in INTELLIGENCE")
    func everyAssistantSectionIsPlaced() {
        // A section's home is a tab (group) title or a row label — declared
        // managers (E7) are tabs of rows, not one row named after the section.
        let pages = catalog.pages(in: .intelligence)
        let labels = Set(pages.flatMap { $0.allFields.map(\.label) + $0.groups.map(\.title) })
        for required in ["Connections", "Model", "Permissions", "Sandbox", "Tool hooks",
                         "Remote channel", "Context privacy",
                         // Declared rows now (E7): each tool's provider row.
                         "Search provider", "Image provider", "Video provider"] {
            #expect(labels.contains(required), "\(required) has no home")
        }
    }

    @Test("Memory, MCP, Language servers and Skills are catalog pages now")
    func formerSidebarRowsArePlaced() {
        let pages = catalog.pages(in: .intelligence)
        let labels = Set(pages.flatMap { $0.allFields.map(\.label) + $0.groups.map(\.title) })
        for required in ["Memory", "MCP servers", "Language servers", "Skills"] {
            #expect(labels.contains(required), "\(required) has no home")
        }
    }

    @Test("navigation depth is uniform — no page nests another page")
    func uniformDepth() {
        for page in catalog.pages {
            #expect(page.path.segments.count == 2, "\(page.path) is not top-level")
        }
    }

    @Test("search keywords reach settings whose label does not contain the query")
    func keywordsIndexed() {
        let fields = catalog.allFields
        func field(matching keyword: String) -> SettingsField? {
            fields.first { $0.keywords.contains(keyword) }
        }
        #expect(field(matching: "api key")?.label == "Connections")
        // MCP servers are declared rows now (E7): "mcp" must land on Tools.
        #expect(field(matching: "mcp").map { Array($0.path.segments.prefix(2)) } == ["intelligence", "tools"])
        // Keyboard is one declared row per shortcut now (E7): "hotkey" must
        // still land on that page.
        #expect(field(matching: "hotkey").map { Array($0.path.segments.prefix(2)) } == ["workspace", "keyboard"])
    }

    @Test("Skills is a page of its own")
    func skillsPage() {
        let skills = catalog.pages(in: .intelligence).first { $0.title == "Skills" }
        #expect(skills != nil)
        #expect(skills?.icon == "sparkles")
    }

    /// The proposals badge is the ONLY signal in the app that skill proposals
    /// are waiting, so it gets a test that fails if the badge is dropped —
    /// and one that fails if it is snapshotted at catalog-build time instead
    /// of read at render time.
    @Test("the Skills page badges the pending proposal count, read live")
    func skillsBadgeIsLive() throws {
        let environment = AppEnvironment.preview()
        let skills = HostSettingsCatalog.build(environment: environment)
            .pages(in: .intelligence).first { $0.title == "Skills" }
        let badge = try #require(skills?.badge, "the Skills page exposes no badge")

        #expect(badge() == 0)

        try environment.skillRegistry.propose(
            name: "demo-skill", description: "A proposal awaiting review.", body: "Do the thing.")

        // Same page value, same closure — a count captured when the catalog was
        // built would still read 0 here.
        #expect(badge() == 1)
        #expect(badge() == environment.skillRegistry.proposals().count)
    }

    @Test("no other page carries a badge")
    func onlySkillsBadges() {
        for page in catalog.pages where page.title != "Skills" {
            #expect(page.badge == nil, "\(page.title) should expose no badge")
        }
    }
}
