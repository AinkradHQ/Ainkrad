// Tests/AinkradTests/MCPToolAdapterTests.swift
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("MCPToolAdapter")
@MainActor
struct MCPToolAdapterTests {
    private func client() -> MCPClient {
        MCPClient(
            transport: StubMCPTransport { message in
                guard let id = message["id"]?.stringValue,
                    let method = message["method"]?.stringValue
                else { return [] }
                switch method {
                case "initialize":
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "result": .object(["capabilities": .object([:])]),
                        ])
                    ]
                case "tools/call":
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "result": .object([
                                "content": .array([
                                    .object(["type": .string("text"), "text": .string("hi from mcp")])
                                ])
                            ]),
                        ])
                    ]
                default:
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "result": .object([:]),
                        ])
                    ]
                }
            })
    }

    /// A client whose `tools/call` always answers with `isError: true` — used to
    /// prove a server-reported tool failure surfaces as a typed `ToolResult`
    /// (isError: true) rather than throwing out of `execute`.
    private func erroringClient() -> MCPClient {
        MCPClient(
            transport: StubMCPTransport { message in
                guard let id = message["id"]?.stringValue,
                    let method = message["method"]?.stringValue
                else { return [] }
                switch method {
                case "initialize":
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "result": .object(["capabilities": .object([:])]),
                        ])
                    ]
                case "tools/call":
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "result": .object([
                                "isError": .bool(true),
                                "content": .array([
                                    .object(["type": .string("text"), "text": .string("boom")])
                                ]),
                            ]),
                        ])
                    ]
                default:
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "result": .object([:]),
                        ])
                    ]
                }
            })
    }

    @Test func namespacesAndForwardsSchema() {
        let desc = MCPToolDescriptor(
            name: "search", description: "web search",
            inputSchema: .object(["type": .string("object")]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: client())
        #expect(adapter.name == "mcp/web/search")
        #expect(adapter.description == "web search")
        #expect(adapter.permission == .write)
        #expect(adapter.parametersSchema["type"]?.stringValue == "object")
    }

    @Test func executeRoutesToClient() async throws {
        let c = client()
        try await c.connect()
        let desc = MCPToolDescriptor(name: "search", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: c)
        let r = try await adapter.execute(.object(["q": .string("swift")]))
        #expect(!r.isError)
        #expect(r.content == "hi from mcp")
    }

    @Test func serverToolErrorSurfacesAsNonCrashingResult() async throws {
        let c = erroringClient()
        try await c.connect()
        let desc = MCPToolDescriptor(name: "search", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: c)
        let r = try await adapter.execute(.object([:]))
        #expect(r.isError)
        #expect(r.content.contains("boom"))
    }

    /// Finding 6: `permission` is a constant `.write`, so without honouring the
    /// server's `destructiveHint` the Full-auto irreversible guard could never
    /// fire for an MCP tool — a trusted server's destructive tool would
    /// auto-approve.
    @Test func destructiveHintDrivesIrreversibility() {
        let destructive = MCPToolDescriptor(
            name: "reset", description: "",
            inputSchema: .object([:]), destructive: true)
        let plain = MCPToolDescriptor(name: "status", description: "", inputSchema: .object([:]))
        #expect(
            MCPToolAdapter(server: "git", descriptor: destructive, client: client())
                .isIrreversible(.object([:])))
        #expect(
            !MCPToolAdapter(server: "git", descriptor: plain, client: client())
                .isIrreversible(.object([:])))
        // A destructive tool is `.write` whatever else it claims.
        #expect(
            MCPToolAdapter(server: "git", descriptor: destructive, client: client())
                .permission == .write)
    }

    /// `readOnlyHint` de-escalates the permission CLASS, so a read stops being
    /// gated as a write. Both flags default false, so a descriptor with no
    /// annotations at all stays `.write` — the host must not invent a safety
    /// claim the server never made.
    @Test func readOnlyHintDrivesPermissionClass() {
        func adapter(readOnly: Bool, destructive: Bool) -> MCPToolAdapter {
            MCPToolAdapter(
                server: "lore",
                descriptor: MCPToolDescriptor(
                    name: "t", description: "",
                    inputSchema: .object([:]),
                    destructive: destructive,
                    readOnly: readOnly),
                client: client())
        }
        #expect(adapter(readOnly: true, destructive: false).permission == .read)
        #expect(adapter(readOnly: false, destructive: false).permission == .write)
        // The contradiction case: a descriptor claiming BOTH is self-contradictory
        // and the safe reading of a contradiction is `.write`.
        #expect(adapter(readOnly: true, destructive: true).permission == .write)
        // No annotations at all — the default.
        #expect(
            MCPToolAdapter(
                server: "lore",
                descriptor: MCPToolDescriptor(
                    name: "t", description: "",
                    inputSchema: .object([:])),
                client: client()
            ).permission == .write)
    }

    /// THE property the whole relaxation rests on: de-escalating the class must
    /// not touch `isIrreversible`. `MCPArgumentRisk` is evaluated independently of
    /// the permission class, and `AgentPermissionPolicy.decide` checks
    /// `isIrreversible` first and unconditionally — so a `readOnly` tool carrying
    /// an option-looking argument still requires approval, even on a trusted
    /// server in every mode.
    @Test func readOnlyToolWithOptionLookingArgumentIsStillIrreversible() {
        let desc = MCPToolDescriptor(
            name: "status", description: "",
            inputSchema: .object([:]),
            destructive: false, readOnly: true)
        let adapter = MCPToolAdapter(server: "git", descriptor: desc, client: client())
        #expect(adapter.permission == .read)
        let risky = JSONValue.object(["ref": .string("--upload-pack=/bin/sh")])
        #expect(adapter.isIrreversible(risky))
        for mode in AgentPermissionMode.allCases {
            #expect(
                AgentPermissionPolicy.decide(
                    toolPermission: adapter.permission, toolName: adapter.name,
                    mode: mode, allowlist: [adapter.name], gateReads: false,
                    isIrreversible: adapter.isIrreversible(risky),
                    isTrusted: true) == .requireApproval)
        }
    }

    /// The user-facing escape hatch survives the de-escalation: `gateReads`
    /// re-gates read-class tools. Driven through the policy directly, since it is
    /// the policy — not the adapter — that owns this behaviour.
    @Test func gateReadsStillGatesAReadOnlyMCPTool() {
        let desc = MCPToolDescriptor(
            name: "status", description: "",
            inputSchema: .object([:]),
            destructive: false, readOnly: true)
        let adapter = MCPToolAdapter(server: "git", descriptor: desc, client: client())
        func decide(gateReads: Bool) -> PermissionDecision {
            AgentPermissionPolicy.decide(
                toolPermission: adapter.permission, toolName: adapter.name,
                mode: .ask, allowlist: [], gateReads: gateReads,
                isIrreversible: adapter.isIrreversible(.object([:])), isTrusted: false)
        }
        #expect(decide(gateReads: false) == .autoApprove)
        #expect(decide(gateReads: true) == .requireApproval)
    }

    /// Proves the OR is one-directional: `destructive: false` must never let
    /// an option-looking argument slip through as reversible.
    @Test func optionLookingArgumentEscalatesEvenWhenHintSaysSafe() {
        let plain = MCPToolDescriptor(
            name: "status", description: "",
            inputSchema: .object([:]), destructive: false)
        let adapter = MCPToolAdapter(server: "git", descriptor: plain, client: client())
        #expect(adapter.isIrreversible(.object(["branch": .string("--upload-pack=/bin/sh")])))
        #expect(!adapter.isIrreversible(.object(["branch": .string("main")])))
    }

    /// This text is what the user reads at the moment they authorise an
    /// irreversible operation. The default `AgentTool` preview dumped raw JSON
    /// (`mcp/gitmage/reset_hard` + `{"args":{...},"repoPath":"/x"}`); it must
    /// read like the host's own tools did (`Git: reset` / `reset — /repo`).
    @Test func approvalPreviewIsHumanReadableNotRawJSON() {
        let desc = MCPToolDescriptor(
            name: "reset_hard", description: "",
            inputSchema: .object([:]), destructive: true)
        let adapter = MCPToolAdapter(server: "gitmage", descriptor: desc, client: client())
        let preview = adapter.approvalPreview(
            .object([
                "repoPath": .string("/x"),
                "args": .object(["ref": .string("HEAD~1")]),
            ]))
        #expect(preview.title == "Gitmage reset hard")
        // The inner `args` values are flattened out — they are the dangerous
        // ones, and "args" itself tells the user nothing.
        #expect(preview.summary == "ref: HEAD~1 · repoPath: /x")
        #expect(!preview.summary.contains("{"), "no raw JSON in the approval prompt")
        #expect(preview.diff == nil)
    }

    /// Non-string scalars and deeper structure must still read as something,
    /// and a huge payload must not push the meaningful part off the HUD.
    @Test func approvalPreviewRendersScalarsAndCapsLength() {
        let desc = MCPToolDescriptor(name: "pr_create", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "gitmage", descriptor: desc, client: client())
        let preview = adapter.approvalPreview(
            .object([
                "draft": .bool(false), "number": .number(7),
                "labels": .array([.string("a"), .string("b")]),
            ]))
        #expect(preview.summary == "draft: false · labels: [2 items] · number: 7")

        let long = adapter.approvalPreview(.object(["body": .string(String(repeating: "x", count: 500))]))
        #expect(long.summary.count < 260)
        #expect(long.summary.hasSuffix("…"))
    }

    /// Every JSON number is a `Double`, and the first version of this preview
    /// rendered integral ones with `Int(n)` — which TRAPS outside `Int`'s
    /// range, i.e. for `1e30` and `±.infinity`, whose `n == n.rounded()` test
    /// is true. That is a crash on the approval-preview path, driven by a
    /// model- or server-controlled value, at the exact moment the user is being
    /// asked to authorise an irreversible call. NO `Double` may trap here: the
    /// property under test is that each of these returns some string at all.
    @Test(
        arguments: [
            7.0, 1.5, -1.5, 0.0, -0.0,
            1e30, -1e30, Double(Int.max), Double(Int.min), 1e300,
            .infinity, -.infinity, .nan,
            .greatestFiniteMagnitude, .leastNonzeroMagnitude,
        ] as [Double])
    func approvalPreviewNeverTrapsOnANumber(_ value: Double) {
        let desc = MCPToolDescriptor(name: "pr_create", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "gitmage", descriptor: desc, client: client())
        let summary = adapter.approvalPreview(.object(["n": .number(value)])).summary
        #expect(summary.hasPrefix("n: "))
        #expect(summary.count > 3, "the value must render as something")
        // Nested too — that branch renders through the same helper.
        let nested = adapter.approvalPreview(.object(["args": .object(["n": .number(value)])])).summary
        #expect(nested.hasPrefix("n: "))
    }

    /// The in-range integral case still reads as an integer, not `7.0`.
    @Test func approvalPreviewStillRendersIntegralNumbersWithoutADecimalPoint() {
        let desc = MCPToolDescriptor(name: "pr_view", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "gitmage", descriptor: desc, client: client())
        #expect(adapter.approvalPreview(.object(["number": .number(7)])).summary == "number: 7")
        #expect(adapter.approvalPreview(.object(["number": .number(1.5)])).summary == "number: 1.5")
    }

    @Test func namespaceParsesBackToServerAndTool() {
        let desc = MCPToolDescriptor(name: "search", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: client())
        let parts = adapter.name.split(separator: "/", maxSplits: 2)
        #expect(parts.count == 3)
        #expect(parts[0] == "mcp")
        #expect(String(parts[1]) == "web")
        #expect(String(parts[2]) == "search")
    }
}
