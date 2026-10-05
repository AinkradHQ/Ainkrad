import AinkradHostRuntime
import Foundation

enum MCPError: Error, Equatable {
    case transport(String)
    case protocolError(String)
    case rpc(code: Int, message: String)
    case notConnected
    /// A `resources/read` that reached the server and came back marked failed
    /// (`ainkrad/isError`). Distinct from `protocolError` because the payload is
    /// the SERVER'S OWN explanation ("no terminal is currently open") and should
    /// reach the model verbatim, not wrapped in host framing about the RPC.
    case resourceFailure(String)
}

struct MCPToolDescriptor: Equatable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    /// MCP `annotations.destructiveHint` — what the SDK's `MCPToolSpec.destructive`
    /// serializes to. Drives `MCPToolAdapter.isIrreversible`, i.e. the Full-auto
    /// approval guard. Defaults to `false` when the server sends no annotations:
    /// the host must not invent a risk claim a server never made.
    let destructive: Bool
    /// MCP `annotations.readOnlyHint`. Drives `MCPToolAdapter.permission`: a tool
    /// that claims `readOnly` and NOT `destructive` is published as `.read`, so it
    /// stops prompting in `.ask` unless the user has turned `gateReads` on. It can
    /// never relax `isIrreversible` — see the reasoning on `MCPToolAdapter.permission`.
    /// Defaults to `false` for the same reason `destructive` does.
    let readOnly: Bool
    /// Ainkrad-specific `annotations["ainkrad/requiresLiveApp"]` — the SDK's
    /// `MCPToolSpec.requiresLiveApp`. Namespaced upstream because it is not a
    /// standard MCP annotation. Drives `AppServerActivator`: only a tool that
    /// claims it needs the window force-opens the app before dispatch.
    ///
    /// Defaults to `false` for the same reason `destructive` does, and with a
    /// sharper consequence: a tool call must never pop a window open on a claim
    /// the server never made. A remote (non-app) server never sends this key,
    /// and nothing about a remote tool could need a local app window anyway.
    let requiresLiveApp: Bool

    init(
        name: String, description: String, inputSchema: JSONValue,
        destructive: Bool = false, readOnly: Bool = false,
        requiresLiveApp: Bool = false
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.destructive = destructive
        self.readOnly = readOnly
        self.requiresLiveApp = requiresLiveApp
    }
}

struct MCPResourceDescriptor: Equatable {
    let uri: String
    let name: String
    let mimeType: String
    /// Standard MCP `description` — the SDK's `MCPResourceSpec.purpose`. Says
    /// WHEN to read the resource, which is the only part the model can act on
    /// when choosing between several; `name` merely labels it. Empty when the
    /// server sends none, so `MCPReadResourceTool` can omit the clause rather
    /// than print a dangling separator.
    let description: String
    /// See `MCPToolDescriptor.requiresLiveApp` — same key, same default.
    let requiresLiveApp: Bool

    init(
        uri: String, name: String, mimeType: String, description: String = "",
        requiresLiveApp: Bool = false
    ) {
        self.uri = uri
        self.name = name
        self.mimeType = mimeType
        self.description = description
        self.requiresLiveApp = requiresLiveApp
    }
}

/// Pure JSON-RPC 2.0 (over `JSONValue`) helpers for the MCP client. String ids
/// keep correlation simple and match `JSONValue.stringValue`.
enum MCPRPC {
    static func request(id: String, method: String, params: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": .string(id),
            "method": .string(method), "params": params,
        ])
    }

    static func notification(method: String, params: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
    }

    /// A message is a response iff it carries an `id`; `result` → success,
    /// `error` → failure. (Messages without `id` are server notifications.)
    static func decodeResponse(_ message: JSONValue) -> Result<(id: String, result: JSONValue), MCPError> {
        guard let id = message["id"]?.stringValue else {
            return .failure(.protocolError("response missing string id"))
        }
        if let error = message["error"] {
            let code = error["code"].flatMap(intValue) ?? 0
            let msg = error["message"]?.stringValue ?? "unknown error"
            return .failure(.rpc(code: code, message: msg))
        }
        return .success((id, message["result"] ?? .object([:])))
    }

    static func decodeToolList(_ result: JSONValue) -> [MCPToolDescriptor] {
        guard case .array(let items)? = result["tools"] else { return [] }
        return items.compactMap { item in
            guard let name = item["name"]?.stringValue else { return nil }
            let annotations = item["annotations"]
            return MCPToolDescriptor(
                name: name,
                description: item["description"]?.stringValue ?? "",
                inputSchema: item["inputSchema"] ?? .object(["type": .string("object")]),
                destructive: annotations?["destructiveHint"].flatMap(boolValue) ?? false,
                readOnly: annotations?["readOnlyHint"].flatMap(boolValue) ?? false,
                requiresLiveApp: annotations?["ainkrad/requiresLiveApp"].flatMap(boolValue) ?? false)
        }
    }

    static func decodeResourceList(_ result: JSONValue) -> [MCPResourceDescriptor] {
        guard case .array(let items)? = result["resources"] else { return [] }
        return items.compactMap { item in
            guard let uri = item["uri"]?.stringValue else { return nil }
            return MCPResourceDescriptor(
                uri: uri,
                name: item["name"]?.stringValue ?? uri,
                mimeType: item["mimeType"]?.stringValue ?? "text/plain",
                description: item["description"]?.stringValue ?? "",
                requiresLiveApp: item["annotations"]?["ainkrad/requiresLiveApp"]
                    .flatMap(boolValue) ?? false)
        }
    }

    /// Flattens a `resources/read` result's `contents` array into plain text.
    static func flattenResourceContents(_ result: JSONValue) -> String {
        guard case .array(let items)? = result["contents"] else { return "" }
        return items.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
    }

    /// True when the message is a server-initiated notification (no id).
    static func isNotification(_ message: JSONValue) -> Bool {
        message["id"] == nil && message["method"] != nil
    }

    private static func boolValue(_ v: JSONValue) -> Bool? {
        if case .bool(let b) = v { return b }
        return nil
    }

    private static func intValue(_ v: JSONValue) -> Int? {
        if case .number(let n) = v {
            guard n.isFinite else { return nil }
            return Int(exactly: n.rounded())
        }
        return nil
    }
}
