import AinkradHostRuntime
import Foundation

enum ToolHookEvent: String, Codable, Equatable, Sendable, CaseIterable {
    case preToolUse, postToolUse
}

/// One user-defined hook. `match` is a tool-name glob (`*` wildcard, e.g.
/// `edit_file`, `mcp/*`, `*`). `command` is a shell command run through the
/// same `ExecutionRouter`/`HostBackend` path `run_terminal` uses; the tool-call
/// context is exposed to it via env vars (`AINKRAD_TOOL_NAME`,
/// `AINKRAD_TOOL_PATH`, `AINKRAD_TOOL_COMMAND`).
struct ToolHook: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var enabled: Bool
    var event: ToolHookEvent
    var match: String
    var command: String
    var timeoutSeconds: Int
}

struct ToolHooksDocument: PersistableDocument {
    static let documentID = "agent-tool-hooks"
    static let currentSchemaVersion = 2

    /// v1 → v2: the 2026-08-02 app rename. A hook's `match` is a tool-name glob,
    /// and a hook that matches nothing is SILENT — no error, no UI signal,
    /// nothing anywhere reports a hook that never fired. This migrator is the
    /// only thing standing between the rename and a user's automation quietly
    /// ceasing to run.
    static let migrators: [DocumentMigrator] = [
        DocumentMigrator(from: 1) { payload in
            guard case .object(var root) = payload,
                case .array(let hooks)? = root["hooks"]
            else { return payload }
            root["hooks"] = .array(
                hooks.map { hook in
                    guard case .object(var fields) = hook,
                        case .string(let match)? = fields["match"]
                    else { return hook }
                    fields["match"] = .string(AppIDRenames.renamedToolName(match))
                    return .object(fields)
                })
            return .object(root)
        }
    ]

    var hooks: [ToolHook]
}

/// Pure tool-name glob matcher (single `*` wildcard, matched greedily). Kept
/// standalone so matching is unit-testable without a live runner.
enum ToolHookMatcher {
    static func matches(pattern: String, toolName: String) -> Bool {
        if pattern == "*" { return true }
        guard pattern.contains("*") else { return pattern == toolName }
        let segments = pattern.components(separatedBy: "*")
        var cursor = toolName.startIndex
        for (i, seg) in segments.enumerated() where !seg.isEmpty {
            guard let range = toolName.range(of: seg, range: cursor..<toolName.endIndex) else { return false }
            if i == 0, range.lowerBound != toolName.startIndex { return false }  // leading anchor
            cursor = range.upperBound
        }
        if let last = segments.last, !last.isEmpty { return toolName.hasSuffix(last) }
        return true
    }
}
