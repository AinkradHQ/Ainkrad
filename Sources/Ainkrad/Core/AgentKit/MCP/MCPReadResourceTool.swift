import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/MCPReadResourceTool.swift
import Foundation

/// Reads one MCP resource on demand.
///
/// Ambient app state still arrives every turn through `AgentContextRegistryHub`
/// → `<workspace_context>`; this tool is the pull-based complement for payloads
/// larger than `AgentContextService.perSourceCharBudget`, which that path
/// tail-truncates. Read-class, so it is gated like any other read.
@MainActor
struct MCPReadResourceTool: AgentTool {
    // `weak`, not `unowned`: in production `agentTools` and `mcpServerRegistry`
    // share `AppEnvironment`'s lifetime, so `unowned` would be safe there — but
    // a caller can construct this tool around a registry it does not otherwise
    // retain (e.g. a temporary passed straight into the initializer), and
    // `unowned` crashes the process the instant that temporary is deallocated.
    // `weak` degrades to a named error result instead.
    weak var registry: MCPServerRegistry?

    let name = "mcp_read_resource"
    let permission: ToolPermissionClass = .read

    /// The guidance half of the description — WHY to reach for this tool. Kept
    /// separate (and first) so the live listing below can never crowd it out.
    static let guidance = """
        Read the full contents of a resource published by an MCP server or Ainkrad app. \
        Use when the workspace context shows a truncated value and you need all of it.
        """

    /// Most resources enumerated in the description. The listing exists so the
    /// model can DISCOVER URIs it would otherwise have to be told by the user —
    /// but it ships in the system prompt on every turn, so it cannot be
    /// unbounded. 20 covers every app shipping today (Terminal 2, Lore 1) with
    /// wide headroom; beyond it the overflow is stated as a count rather than
    /// silently dropped, so the model knows to ask rather than concluding the
    /// list it can see is the whole world.
    static let maxListedResources = 20

    /// COMPUTED, not stored — this is the entire point of the listing.
    ///
    /// `AgentSession.allowedSchemas()` re-reads `AgentToolRegistry.schemas` when
    /// it builds each request, and `AgentTool.schema` reads `description` then.
    /// So a resource that appears when the user opens an app shows up in the
    /// next turn's tool list. As a stored `let` (which this was) the string was
    /// frozen at `AppEnvironment` bootstrap, when no app server is connected yet
    /// — the listing would have been permanently empty.
    var description: String {
        let all = registry?.discoveredResources() ?? []
        // Degrade to guidance alone: a "Available resources:" header over an
        // empty list reads as a broken template, and actively misleads a model
        // into thinking discovery ran and found nothing worth naming.
        guard !all.isEmpty else { return Self.guidance }

        // The descriptor's `description` says WHEN to read the resource, which
        // is the part that actually lets the model choose between several —
        // the name alone only labels them. Appended rather than substituted so
        // a server that sends none still produces a well-formed line.
        let listed = all.prefix(Self.maxListedResources).map { entry in
            let line =
                "- server \"\(entry.server)\", uri \"\(entry.descriptor.uri)\": "
                + entry.descriptor.name
            let purpose = entry.descriptor.description
            return purpose.isEmpty ? line : line + " — " + purpose
        }
        var text =
            Self.guidance + "\n\nCurrently available resources:\n"
            + listed.joined(separator: "\n")
        let omitted = all.count - listed.count
        if omitted > 0 {
            text +=
                "\n- (\(omitted) more resource\(omitted == 1 ? "" : "s") not listed; "
                + "call with a uri you already know, or ask the user.)"
        }
        return text
    }

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object([
                    "type": .string("string"),
                    "description": .string("Server or app id that owns the resource."),
                ]),
                "uri": .object([
                    "type": .string("string"),
                    "description": .string("Resource URI, as reported by the server."),
                ]),
            ]),
            "required": .array([.string("server"), .string("uri")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let server = input["server"]?.stringValue, !server.isEmpty else {
            throw ToolError.message("mcp_read_resource requires a \"server\".")
        }
        guard let uri = input["uri"]?.stringValue, !uri.isEmpty else {
            throw ToolError.message("mcp_read_resource requires a \"uri\".")
        }
        guard let registry, let client = registry.client(for: server) else {
            return ToolResult(content: "No connected MCP server named '\(server)'.", isError: true)
        }
        do {
            return ToolResult(content: try await client.readResource(uri: uri), isError: false)
        } catch MCPError.resourceFailure(let reason) {
            // The resource itself reported failure. Surface it as an ERROR
            // result carrying the server's own words — returning it as content
            // would hand the model "no terminal is currently open" as though it
            // were the buffer, and host framing about a failed read would bury
            // the one sentence that explains what to do instead.
            return ToolResult(content: reason, isError: true)
        } catch {
            return ToolResult(
                content: "Reading '\(uri)' from '\(server)' failed: \(error)",
                isError: true)
        }
    }
}
