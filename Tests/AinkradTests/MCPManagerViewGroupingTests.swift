import Testing

@testable import Ainkrad

@Suite("MCP server grouping")
struct MCPManagerViewGroupingTests {
    let configs = [
        MCPServerConfig(
            id: "brave", displayName: "Brave", transport: .stdio,
            command: "/usr/bin/brave", enabled: true, trusted: false),
        MCPServerConfig(
            id: "gitmage", displayName: "Git Mage", transport: .inProcess,
            enabled: true, trusted: false, appID: "gitmage"),
        MCPServerConfig(
            id: "terminal", displayName: "Terminal", transport: .inProcess,
            enabled: true, trusted: true, appID: "terminal"),
    ]

    @Test("in-process configs are grouped as apps")
    func appConfigsAreInProcessOnly() {
        #expect(MCPServerGrouping.appConfigs(from: configs).map(\.id) == ["gitmage", "terminal"])
    }

    @Test("every other transport stays in the external group")
    func externalConfigsExcludeApps() {
        #expect(MCPServerGrouping.externalConfigs(from: configs).map(\.id) == ["brave"])
    }

    @Test("the two groups partition the configs with no loss or overlap")
    func groupsPartition() {
        let app = MCPServerGrouping.appConfigs(from: configs).map(\.id)
        let external = MCPServerGrouping.externalConfigs(from: configs).map(\.id)
        #expect(Set(app).isDisjoint(with: Set(external)))
        #expect(Set(app).union(external) == Set(configs.map(\.id)))
    }

    @Test("the app and external trust copy differ")
    func trustHelpDiffersByContext() {
        #expect(MCPServerGrouping.appTrustHelp != MCPServerGrouping.externalTrustHelp)
    }

    @Test("only the app variant discloses the in-process/live-state grant")
    func trustHelpAppMentionsInProcess() {
        #expect(MCPServerGrouping.appTrustHelp.contains("in-process"))
        #expect(MCPServerGrouping.appTrustHelp.contains("live state"))
        #expect(!MCPServerGrouping.externalTrustHelp.contains("in-process"))
    }

    @Test("both variants disclose auto-approval without prompting and the irreversible-action gate")
    func trustHelpBothDiscloseAutoApproveAndGate() {
        for help in [MCPServerGrouping.appTrustHelp, MCPServerGrouping.externalTrustHelp] {
            #expect(help.contains("without prompting"))
            #expect(help.contains("Irreversible actions still require your confirmation"))
        }
    }

    // MARK: - Connected badge

    @Test("a tools-only server reads as tools alone")
    func badgeToolsOnly() {
        #expect(MCPServerGrouping.connectedBadgeText(toolCount: 35, resourceCount: 0) == "35 tools")
    }

    /// The Terminal case: 0 tools by design, 2 resources. Must never read
    /// "0 tools", which users take to mean the app is broken.
    @Test("a resources-only server never reads as 0 tools")
    func badgeResourcesOnly() {
        let text = MCPServerGrouping.connectedBadgeText(toolCount: 0, resourceCount: 2)
        #expect(text == "2 resources")
        #expect(!text.contains("0 tool"))
    }

    @Test("a server publishing both shows both")
    func badgeBoth() {
        #expect(
            MCPServerGrouping.connectedBadgeText(toolCount: 8, resourceCount: 1)
                == "8 tools · 1 resource")
    }

    @Test("a server publishing nothing still reports the successful connection")
    func badgeNeither() {
        #expect(MCPServerGrouping.connectedBadgeText(toolCount: 0, resourceCount: 0) == "connected")
    }

    @Test("counts of one are singular")
    func badgeSingular() {
        #expect(MCPServerGrouping.connectedBadgeText(toolCount: 1, resourceCount: 0) == "1 tool")
    }

    // MARK: - Resource labels

    @Test("a publisher-supplied title wins over anything derived from the URI")
    func resourceLabelPrefersTitle() {
        #expect(
            ToolPresentation.resourceLabel(name: "Terminal buffer", uri: "terminal://buffer")
                == "Terminal buffer")
    }

    /// `MCPRPC.decodeResourceList` defaults a missing `name` to the URI, so this
    /// is the path that would otherwise render "Terminal://buffer".
    @Test("a missing title falls back to the URI's last segment, not the raw URI")
    func resourceLabelFallsBackToURISegment() {
        #expect(
            ToolPresentation.resourceLabel(name: "terminal://buffer", uri: "terminal://buffer")
                == "Buffer")
        #expect(
            ToolPresentation.resourceLabel(name: "", uri: "app://logs/today-tail")
                == "Today tail")
    }

    @Test("a URI with no usable segment degrades to the URI itself rather than an empty label")
    func resourceLabelDegradesToURI() {
        #expect(ToolPresentation.resourceLabel(name: "scheme://", uri: "scheme://") == "scheme://")
    }
}
