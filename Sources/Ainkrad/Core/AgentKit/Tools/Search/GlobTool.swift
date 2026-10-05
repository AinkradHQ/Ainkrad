import AinkradHostRuntime
import Foundation

/// Filename/path glob over the workspace root, honoring WorkspaceFileIndex's
/// ignore rules. Sorted, capped. Read-class.
struct GlobTool: AgentTool {
    static let maxPaths = 500
    static let maxFilesScanned = 20_000
    let rootProvider: @MainActor () -> URL

    let name = "glob"
    let description = "Find files by glob pattern (e.g. **/*.swift) under the workspace root. Returns matching paths."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "pattern": .object([
                    "type": .string("string"),
                    "description": .string("Glob, e.g. **/*.swift or src/*.ts."),
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Optional subdirectory (absolute or relative to root)."),
                ]),
            ]),
            "required": .array([.string("pattern")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let pattern = input["pattern"]?.stringValue, !pattern.isEmpty else {
            throw ToolError.message("glob requires a non-empty \"pattern\".")
        }
        let base = resolvedBase(input["path"]?.stringValue)
        let maxFiles = Self.maxFilesScanned

        // Walk + glob matching is heavy for large trees; run off the
        // @MainActor so it can't freeze the UI (e.g. path: "/").
        let matched: [String] = try await Task.detached(priority: .userInitiated) {
            func relative(_ path: String, to base: String) -> String {
                guard path.hasPrefix(base) else { return path }
                return String(path.dropFirst(base.count)).drop(while: { $0 == "/" }).description
            }
            var matched: [String] = []
            for url in WorkspaceFileIndex.fileURLs(under: base, maxFiles: maxFiles) {
                try Task.checkCancellation()
                let rel = relative(url.path, to: base.path)
                if GlobMatcher.matches(rel, pattern: pattern) { matched.append(url.path) }
            }
            return matched.sorted()
        }.value

        if matched.isEmpty { return ToolResult(content: "No files match \(pattern).", isError: false) }
        let capped = matched.prefix(Self.maxPaths)
        var body = capped.joined(separator: "\n")
        if matched.count > Self.maxPaths { body += "\n… (\(matched.count - Self.maxPaths) more)" }
        return ToolResult(content: body, isError: false)
    }

    private func resolvedBase(_ path: String?) -> URL {
        let root = rootProvider()
        guard let path, !path.isEmpty else { return root }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Glob", summary: input["pattern"]?.stringValue ?? "?", diff: nil)
    }
}
