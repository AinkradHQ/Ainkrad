import AinkradAppKit
// Tests/AinkradTests/GitMageMCPParityTests.swift
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// Task 15: the host's side of the contract that let the bespoke `git_op` /
/// `pr_op` tools be deleted.
///
/// Deliberately driven through a STAND-IN `MCPAppServer`, not the real Git Mage
/// plugin: the host must be able to prove this without the plugin present, and a
/// test that needed a sideloaded `.ainkradapp` would only run on a developer's
/// machine. The stand-in mirrors the shape of the four classification cases
/// GitMage publishes — a read-only tool, a `destructive: true` tool, a split
/// twin's safe half, and a PR tool — so the assertions below are about the HOST
/// path (registry → adapter → permission gate), which is what actually changed.
@MainActor
@Suite("Git Mage over MCP — parity")
struct GitMageMCPParityTests {
    // MARK: - fixture

    /// Stands in for `GitMageMCPServer.make(...)`. Tool names and hints are
    /// copied from GitMage's published tables so the namespaced names asserted
    /// here are the real ones.
    private func gitMageStandIn() -> MCPAppServer {
        let server = MCPAppServer(appID: "gitmage")
        for spec in [
            MCPToolSpec(
                name: "status", description: "Show the working-tree status.",
                schemaJSON: #"{"type":"object"}"#, readOnly: true
            ) { _ in
                AgentActionResult(text: "clean", isError: false)
            },
            MCPToolSpec(
                name: "reset", description: "Reset with a non-destructive mode.",
                schemaJSON: #"{"type":"object"}"#
            ) { _ in
                AgentActionResult(text: "reset", isError: false)
            },
            MCPToolSpec(
                name: "reset_hard", description: "Hard-reset, discarding changes.",
                schemaJSON: #"{"type":"object"}"#, destructive: true
            ) { _ in
                AgentActionResult(text: "reset --hard", isError: false)
            },
            MCPToolSpec(
                name: "pr_merge", description: "Merge a pull request.",
                schemaJSON: #"{"type":"object"}"#, destructive: true
            ) { _ in
                AgentActionResult(text: "merged", isError: false)
            },
        ] {
            server.addTool(spec)
        }
        return server
    }

    private func activator() -> AppServerActivator {
        AppServerActivator(
            servers: ["gitmage": gitMageStandIn()],
            isAppOpen: { _ in true }, requestOpen: { _ in },
            availability: { _ in .available })
    }

    /// A connected registry with Git Mage published as an `.inProcess` server.
    private func connectedRegistry(trusted: Bool) async -> MCPServerRegistry {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        configs.upsert(
            MCPServerConfig(
                id: "gitmage", displayName: "Git Mage",
                transport: .inProcess, enabled: true,
                trusted: trusted, appID: "gitmage"))
        let registry = MCPServerRegistry(configStore: configs, activator: activator())
        await registry.connectEnabled()
        return registry
    }

    /// The permission decision `AgentSession.execute` would reach for this tool,
    /// wired exactly as `bootstrapSession` wires it (`mcpTrust` → `isToolTrusted`).
    private func decision(
        for tool: any AgentTool, input: JSONValue,
        registry: MCPServerRegistry
    ) -> PermissionDecision {
        AgentPermissionPolicy.decide(
            toolPermission: tool.permission, toolName: tool.name,
            mode: .ask, allowlist: [], gateReads: false,
            isIrreversible: tool.isIrreversible(input),
            isTrusted: registry.isToolTrusted(tool.name))
    }

    // MARK: - the bespoke tools are gone, the MCP ones are there

    @Test(
        "git operations are published as namespaced mcp/gitmage/* tools",
        .timeLimit(.minutes(1)))
    func namespacedToolsArePresent() async {
        let mcp = await connectedRegistry(trusted: false)
        let registry = AgentToolRegistry(
            tools: [ReadFileTool()],
            dynamicTools: { [weak mcp] in mcp?.currentTools() ?? [] })
        #expect(registry.tool(named: "mcp/gitmage/status") != nil)
        #expect(registry.tool(named: "mcp/gitmage/reset_hard") != nil)
        #expect(registry.tool(named: "mcp/gitmage/pr_merge") != nil)
    }

    @Test(
        "the bespoke git_op / pr_op tools are no longer reachable by name",
        .timeLimit(.minutes(1)))
    func bespokeToolNamesAreAbsent() async {
        let mcp = await connectedRegistry(trusted: false)
        let registry = AgentToolRegistry(
            tools: [ReadFileTool()],
            dynamicTools: { [weak mcp] in mcp?.currentTools() ?? [] })
        #expect(registry.tool(named: "git_op") == nil)
        #expect(registry.tool(named: "pr_op") == nil)
        // Nothing on the MCP path may reintroduce the old flat names: every
        // adapter is namespaced, so an unnamespaced git_op could only come back
        // from a re-registered host tool.
        #expect(!mcp.currentTools().contains { $0.name == "git_op" || $0.name == "pr_op" })
    }

    // MARK: - trust gating

    /// Driven through `reset` rather than `status`: since the adapter honours
    /// `readOnlyHint`, `status` is now `.read` class and auto-approves in `.ask`
    /// on its own merits (see `untrustedReadOnlyToolIsNoLongerGated` below).
    /// `reset` is the non-destructive WRITE, which is what "gated because
    /// untrusted" actually means now.
    @Test(
        "an untrusted Git Mage has its non-destructive write tools gated",
        .timeLimit(.minutes(1)))
    func untrustedIsGated() async throws {
        let mcp = await connectedRegistry(trusted: false)
        let tool = try #require(mcp.currentTools().first { $0.name == "mcp/gitmage/reset" })
        #expect(!mcp.isToolTrusted(tool.name))
        #expect(tool.permission == .write)
        #expect(
            decision(for: tool, input: .object(["repoPath": .string("/r")]), registry: mcp)
                == .requireApproval)
    }

    /// The UX payoff of honouring `readOnlyHint`: `mcp/gitmage/status` no longer
    /// prompts in `.ask` on an UNTRUSTED server. Previously every MCP tool was a
    /// constant `.write`, so a `status` call raised the same HUD prompt a
    /// `reset_hard` did — which is what trained reflexive approval.
    @Test(
        "an untrusted Git Mage's read-only tools no longer prompt",
        .timeLimit(.minutes(1)))
    func untrustedReadOnlyToolIsNoLongerGated() async throws {
        let mcp = await connectedRegistry(trusted: false)
        let tool = try #require(mcp.currentTools().first { $0.name == "mcp/gitmage/status" })
        #expect(!mcp.isToolTrusted(tool.name))
        #expect(tool.permission == .read)
        #expect(
            decision(for: tool, input: .object(["repoPath": .string("/r")]), registry: mcp)
                == .autoApprove)
    }

    @Test(
        "a trusted Git Mage auto-approves its non-destructive tools",
        .timeLimit(.minutes(1)))
    func trustedIsAutoApproved() async throws {
        let mcp = await connectedRegistry(trusted: true)
        let tool = try #require(mcp.currentTools().first { $0.name == "mcp/gitmage/status" })
        #expect(mcp.isToolTrusted(tool.name))
        #expect(
            decision(for: tool, input: .object(["repoPath": .string("/r")]), registry: mcp)
                == .autoApprove)
    }

    // MARK: - the four irreversibility sources

    @Test(
        "a destructive hint makes the tool irreversible even for a trusted server",
        .timeLimit(.minutes(1)))
    func destructiveHintIsIrreversible() async throws {
        let mcp = await connectedRegistry(trusted: true)
        for name in ["mcp/gitmage/reset_hard", "mcp/gitmage/pr_merge"] {
            let tool = try #require(mcp.currentTools().first { $0.name == name })
            let input = JSONValue.object(["repoPath": .string("/r")])
            #expect(tool.isIrreversible(input))
            #expect(decision(for: tool, input: input, registry: mcp) == .requireApproval)
        }
    }

    /// The replacement for `GitOpTool.optionLookingValue`. `status` is
    /// `readOnly: true` and `destructive: false` — the weakest possible static
    /// hint — so if the argument check did not run, this would auto-approve on a
    /// trusted server. That was the argument-injection hole.
    @Test(
        "an option-looking argument is irreversible regardless of the static hint",
        .timeLimit(.minutes(1)))
    func optionLookingArgumentEscalates() async throws {
        let mcp = await connectedRegistry(trusted: true)
        let tool = try #require(mcp.currentTools().first { $0.name == "mcp/gitmage/status" })
        for offending in ["--upload-pack=/bin/sh", "ext::sh -c whoami"] {
            let input = JSONValue.object([
                "repoPath": .string("/r"),
                "args": .object(["ref": .array([.string(offending)])]),
            ])
            #expect(tool.isIrreversible(input), "\(offending) must escalate")
            #expect(decision(for: tool, input: input, registry: mcp) == .requireApproval)
        }
    }

    /// The two argument-shaped cases the old `isIrreversible` special-cased are
    /// now split tools: the SAFE half stays non-destructive, and its dangerous
    /// argument is refused server-side rather than silently honoured. Host-side,
    /// what must hold is that the safe half is not treated as irreversible while
    /// the twin is — otherwise the split would have bought nothing.
    @Test(
        "the split twins carry the classification the old per-call check did",
        .timeLimit(.minutes(1)))
    func splitTwinsCarryTheClassification() async throws {
        let mcp = await connectedRegistry(trusted: true)
        let safe = try #require(mcp.currentTools().first { $0.name == "mcp/gitmage/reset" })
        let twin = try #require(mcp.currentTools().first { $0.name == "mcp/gitmage/reset_hard" })
        let input = JSONValue.object([
            "repoPath": .string("/r"),
            "args": .object(["ref": .string("HEAD~1")]),
        ])
        #expect(!safe.isIrreversible(input))
        #expect(twin.isIrreversible(input))
    }
}
