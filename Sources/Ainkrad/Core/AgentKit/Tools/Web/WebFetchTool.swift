import AinkradHostRuntime
import Foundation

/// Fetches a URL and returns readable text/markdown, byte-capped like
/// `ReadFileTool`. Read-class: auto-approves unless `gateReads`. SSRF is
/// refused at the boundary via `WebURLValidator`; only text/html/json bodies
/// are returned.
struct WebFetchTool: AgentTool {
    static let maxBytes = 256 * 1024
    let http: DataHTTPClient

    let name = "web_fetch"
    let description = "Fetch an http(s) URL and return its readable text/markdown content (byte-capped)."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object([
                    "type": .string("string"),
                    "description": .string("Absolute http(s) URL to fetch."),
                ]),
                "maxBytes": .object([
                    "type": .string("number"),
                    "description": .string("Optional byte cap (<= 262144)."),
                ]),
            ]),
            "required": .array([.string("url")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let raw = input["url"]?.stringValue, !raw.isEmpty else {
            throw ToolError.message("web_fetch requires a non-empty \"url\".")
        }
        let url = try WebURLValidator.validate(raw)
        var cap = Self.maxBytes
        // Clamp as Double BEFORE `Int(_:)` — `Int(1e20)` traps (uncatchable),
        // and this input is model-controlled. min() keeps it in Int range.
        if case .number(let n)? = input["maxBytes"], n >= 1 { cap = Int(min(n, Double(Self.maxBytes))) }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("text/html,application/json,text/plain", forHTTPHeaderField: "Accept")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw ToolError.message("web_fetch failed for \(raw): \(error.localizedDescription).")
        }
        // Re-validate the final (possibly redirected) URL host.
        if let final = response.url?.absoluteString { _ = try WebURLValidator.validate(final) }
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("web_fetch got HTTP \(response.statusCode) for \(raw).")
        }
        let rawType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let media = rawType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? rawType
        guard media == "application/json" || media.hasPrefix("text/") else {
            throw ToolError.message("web_fetch only returns text/* or application/json; got \"\(rawType)\".")
        }
        var capped = Data(data.prefix(cap))
        var body = String(data: capped, encoding: .utf8)
        var trims = 0
        while body == nil, trims < 3, !capped.isEmpty {
            capped.removeLast()
            trims += 1
            body = String(data: capped, encoding: .utf8)
        }
        guard let body else {
            throw ToolError.message("web_fetch response was not valid UTF-8 text.")
        }
        let text = media == "text/html" ? HTMLTextExtractor.plainText(from: body) : body
        return ToolResult(content: text, isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Fetch URL", summary: input["url"]?.stringValue ?? "?", diff: nil)
    }
}
