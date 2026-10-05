import AinkradHostRuntime
import Foundation

/// Regex content search over the workspace root, honoring WorkspaceFileIndex
/// ignore rules. Skips files over the read cap and non-UTF-8 (binary) files.
/// Returns file:line:preview, capped. Read-class.
struct GrepTool: AgentTool {
    static let maxMatchesDefault = 100
    static let maxFilesScanned = 20_000
    let rootProvider: @MainActor () -> URL

    let name = "grep"
    let description = "Regex content search over the workspace root. Returns file:line:preview matches, capped."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "pattern": .object([
                    "type": .string("string"),
                    "description": .string("Regular expression to search for."),
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Optional subdirectory to scope the search."),
                ]),
                "glob": .object([
                    "type": .string("string"),
                    "description": .string("Optional file glob to restrict which files are scanned."),
                ]),
                "caseInsensitive": .object(["type": .string("boolean")]),
                "maxMatches": .object([
                    "type": .string("number"),
                    "description": .string("Cap on total matches (default 100, max 10000)."),
                ]),
            ]),
            "required": .array([.string("pattern")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let pattern = input["pattern"]?.stringValue, !pattern.isEmpty else {
            throw ToolError.message("grep requires a non-empty \"pattern\".")
        }
        var options: NSRegularExpression.Options = []
        if case .bool(true)? = input["caseInsensitive"] { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            throw ToolError.message("grep pattern is not a valid regular expression.")
        }
        var cap = Self.maxMatchesDefault
        // NOTE: `maxMatches` is model-controlled input. Int(Double) traps
        // uncatchably on NaN/±inf/out-of-range, so clamp in Double space
        // BEFORE converting — never Int() an unclamped Double.
        if case .number(let n)? = input["maxMatches"], n >= 1 {
            cap = Int(min(n, Double(Self.maxMatchesDefault) * 100))  // sane hard ceiling
        }
        let glob = input["glob"]?.stringValue
        let base = resolvedBase(input["path"]?.stringValue)
        let maxFiles = Self.maxFilesScanned
        let maxBytes = ReadFileTool.maxBytes

        // Heavy work (filesystem walk, per-file read/decode, per-line regex
        // matching) is moved off the @MainActor so a huge tree or an adversarial
        // regex can't freeze the UI. Only Sendable values cross the boundary;
        // NSRegularExpression is safe to use for matching from multiple threads.
        let lines: [String] = try await Task.detached(priority: .userInitiated) {
            func relative(_ path: String, to base: String) -> String {
                guard path.hasPrefix(base) else { return path }
                return String(path.dropFirst(base.count)).drop(while: { $0 == "/" }).description
            }
            var lines: [String] = []
            for url in WorkspaceFileIndex.fileURLs(under: base, maxFiles: maxFiles) {
                if lines.count >= cap { break }
                try Task.checkCancellation()
                if let glob, !GlobMatcher.matches(url.lastPathComponent, pattern: glob),
                    !GlobMatcher.matches(relative(url.path, to: base.path), pattern: glob)
                {
                    continue
                }
                // Stat the resolved path so a symlink to a huge file is gated by
                // its true target size, not the symlink's own (tiny) size.
                let statPath = url.resolvingSymlinksInPath().path
                if let size = try? FileManager.default.attributesOfItem(atPath: statPath)[.size] as? Int,
                    size > maxBytes
                {
                    continue
                }
                guard let data = try? Data(contentsOf: url),
                    let text = String(data: data, encoding: .utf8)
                else { continue }  // skip binary
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    if lines.count >= cap { break }
                    let s = String(line)
                    if regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                        let preview = s.trimmingCharacters(in: .whitespaces).prefix(200)
                        lines.append("\(url.path):\(index + 1): \(preview)")
                    }
                }
            }
            return lines
        }.value

        if lines.isEmpty { return ToolResult(content: "No matches for /\(pattern)/.", isError: false) }
        return ToolResult(content: lines.joined(separator: "\n"), isError: false)
    }

    private func resolvedBase(_ path: String?) -> URL {
        let root = rootProvider()
        guard let path, !path.isEmpty else { return root }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Grep", summary: input["pattern"]?.stringValue ?? "?", diff: nil)
    }
}
