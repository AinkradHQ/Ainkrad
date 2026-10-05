import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/MCPToolAdapter.swift
import Foundation

/// Presents one discovered MCP tool to the LLM as a native `AgentTool`. Names
/// are namespaced `mcp/<server>/<tool>` to avoid collisions across servers and
/// with built-in tools. Trust is resolved by `MCPServerRegistry.isToolTrusted`,
/// which matches the namespaced name against the registry's REAL discovered
/// `(server, tool)` pairs by exact equality — deliberately NOT by splitting the
/// string on `/` (a server id may contain `/`, and a naive split would let one
/// server borrow another's trust). Do not "simplify" that lookup to a split.
/// MCP tools are `.write` class (gated) unless the server marks them
/// `readOnlyHint` without `destructiveHint` — see `permission` for why that
/// de-escalation is safe and where it stops. A trusted server auto-approves them
/// via the permission seam (Task 9), never an irreversible op.
struct MCPToolAdapter: AgentTool {
    let server: String
    let descriptor: MCPToolDescriptor
    let client: MCPClient

    var name: String { "mcp/\(server)/\(descriptor.name)" }
    var description: String { descriptor.description }
    var parametersSchema: JSONValue { descriptor.inputSchema }
    /// The permission class honours the server's `annotations.readOnlyHint`, but
    /// only when the same descriptor does NOT also claim `destructiveHint`. A
    /// descriptor asserting both is self-contradictory, and the safe reading of a
    /// contradiction is `.write`.
    ///
    /// WHY this changed from a constant `.write`: across the three current
    /// adopters every read was gated as a write, so `mcp/gitmage/status`,
    /// `mcp/lore/list_tags` and friends all prompted in `.ask`. A gate that fires
    /// on `list_tags` trains the user to click Approve reflexively, which corrodes
    /// the gate for the calls that actually matter — a worse security outcome than
    /// this relaxation.
    ///
    /// Why the relaxation is bounded (see `AgentPermissionPolicy.decide`, whose
    /// exact ordering this reasoning depends on):
    /// - `isIrreversible` is checked FIRST and UNCONDITIONALLY, before class,
    ///   mode, allowlist and trust. So `destructiveHint` OR an option-looking
    ///   argument (`MCPArgumentRisk`) still forces approval no matter what this
    ///   property says. `readOnly` can de-escalate the CLASS; it can never bypass
    ///   the irreversible gate.
    /// - `.read` auto-approves in `.ask`/`.autoApprove` only when `gateReads` is
    ///   false — an existing user setting, so a user who wants reads gated already
    ///   has the switch.
    ///
    /// The honest threat model: this trusts a server's self-reported `readOnly`. A
    /// lying server could mark a writing tool read-only and have it auto-approve in
    /// `.ask`. That is ACCEPTED, not prevented, because (a) the same server already
    /// self-reports `destructive`, so this is not a new axis of trust, (b) the
    /// irreversible backstop is independent of the server's claims for the
    /// argument-risk half, and (c) `gateReads` exists. Nothing here makes a
    /// dishonest server safe.
    ///
    /// This is a DELIBERATE, SCOPED EXCEPTION to the "hints may only escalate"
    /// rule stated on `isIrreversible` below. The exception applies to the
    /// permission class only; the escalate-only property still holds absolutely
    /// for `isIrreversible`. Anyone reading the OR down there and this line
    /// together should know the two were reconciled on purpose, not by accident.
    var permission: ToolPermissionClass {
        descriptor.readOnly && !descriptor.destructive ? .read : .write
    }

    /// Honours the server's own `annotations.destructiveHint` OR'd with a
    /// per-call argument-risk check. `destructiveHint` alone is a static
    /// per-tool boolean and can't express per-call irreversibility (a git
    /// style tool with a benign-looking `operation` but an
    /// `--upload-pack=<cmd>` argument). `MCPArgumentRisk` generalizes
    /// the host's old git-only check off git so that hole is closed for every
    /// MCP tool, not just git's.
    ///
    /// The OR is one-directional by design: hints may only ESCALATE, never
    /// de-escalate. A server declaring `destructive: false` (or `readOnly:
    /// true`) must never be able to bypass the argument-risk check — do not
    /// "simplify" this into a short-circuit that trusts the hint when it says
    /// safe.
    func isIrreversible(_ input: JSONValue) -> Bool {
        descriptor.destructive || MCPArgumentRisk.hasOptionLookingValue(input)
    }

    /// What the user reads at the moment they authorise an irreversible call,
    /// so it must not be a raw JSON dump. The default `AgentTool` preview
    /// rendered `mcp/gitmage/reset_hard` + `{"args":{"ref":"HEAD~1"},...}`; the
    /// host's own git tool used to say `Git: reset` / `reset — /repo`, and this
    /// restores that register for every MCP tool.
    ///
    /// The title goes through `ToolPresentation.humanize`, the ONE place that
    /// knows both MCP spellings (`mcp/…` and `mcp__…`) — deliberately not a
    /// second copy of that prefix logic here.
    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(
            title: ToolPresentation.humanize(name),
            summary: Self.summarize(input), diff: nil)
    }

    /// A readable one-line rendering of the call's arguments.
    ///
    /// Flattens exactly one level of nesting, because the shape MCP payloads
    /// actually take is a flat envelope plus a single `args`/`arguments` object
    /// (`{"repoPath": "/x", "args": {"ref": "HEAD~1"}}`), and the user needs the
    /// inner values — those are the dangerous ones — not the word "args".
    /// Deeper structure is summarised rather than expanded, and the whole line
    /// is capped, so a large payload can never push the meaningful part of the
    /// prompt off the HUD.
    private static func summarize(_ input: JSONValue) -> String {
        guard case .object(let root) = input, !root.isEmpty else { return scalar(input) ?? "" }
        var parts: [String] = []
        for key in root.keys.sorted() {
            guard let value = root[key] else { continue }
            if case .object(let nested) = value {
                for inner in nested.keys.sorted() {
                    guard let innerValue = nested[inner] else { continue }
                    parts.append("\(inner): \(scalar(innerValue) ?? shape(innerValue))")
                }
            } else {
                parts.append("\(key): \(scalar(value) ?? shape(value))")
            }
        }
        let line = parts.joined(separator: " · ")
        return line.count <= summaryLimit ? line : String(line.prefix(summaryLimit)) + "…"
    }
    private static let summaryLimit = 240

    /// The value as plain text, or nil when it is not a scalar.
    private static func scalar(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s): return s
        case .bool(let b): return "\(b)"
        // `Int(exactly:)`, never `Int(n)`. Every JSON number is a `Double`, and
        // `Int(Double)` TRAPS outside `Int`'s range — for exactly the values an
        // `n == n.rounded()` test waves through: any integral magnitude past
        // `Int.max` (`1e30`), and `±.infinity`, whose `.rounded()` is itself.
        // This runs on the approval-preview path with a model- or
        // server-controlled value, so a trap here crashes the app at the moment
        // the user is being asked to authorise an irreversible call.
        case .number(let n): return Int(exactly: n).map(String.init) ?? "\(n)"
        case .null: return "null"
        case .array, .object: return nil
        }
    }

    /// A non-scalar's shape, so a nested payload still reads as something
    /// rather than vanishing from the prompt.
    private static func shape(_ value: JSONValue) -> String {
        switch value {
        case .array(let items): return "[\(items.count) items]"
        case .object(let dict): return "{\(dict.count) fields}"
        default: return scalar(value) ?? ""
        }
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        do {
            let text = try await client.callTool(name: descriptor.name, arguments: input)
            return ToolResult(content: text, isError: false)
        } catch let error as MCPError {
            // Never crash the session on a server/parse failure — surface it as
            // a typed error result the LLM (and the user) can see.
            return ToolResult(content: "MCP tool \(name) failed: \(error)", isError: true)
        }
    }
}
