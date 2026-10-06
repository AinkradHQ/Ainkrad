import AinkradHostRuntime
import Foundation

/// Token-free tint selector so the mapping stays pure and unit-testable; the
/// view resolves it to a real theme color.
enum ToolTint: Equatable { case primary, secondary }

/// Pure `tool name → visual identity` mapping for transcript tool cards.
/// No SwiftUI, no `AppEnvironment` — unit-tested like `CommandPaletteView.filter`.
struct ToolPresentation: Equatable {
    let icon: String
    let tint: ToolTint
    let label: String

    static func `for`(toolName name: String) -> ToolPresentation {
        let (icon, tint) = iconAndTint(for: name)
        return ToolPresentation(icon: icon, tint: tint, label: humanize(name))
    }

    /// "run_terminal" → "Run terminal"; strips the MCP namespace prefix and
    /// collapses the separators MCP names carry ("mcp__linear__create_issue" →
    /// "Linear create issue", "mcp/gitmage/reset_hard" → "Gitmage reset hard").
    /// A name with no underscore is returned unchanged — this is the timeline's
    /// existing contract (pinned by `humanizeReplacesUnderscoresAndCapitalizes`),
    /// kept as-is here.
    static func humanize(_ name: String) -> String {
        let base = mcpRemainder(name).map { $0.replacingOccurrences(of: "/", with: "_") } ?? name
        guard base.contains("_") else { return base }
        return titleCase(base)
    }

    private static func titleCase(_ base: String) -> String {
        let spaced = base.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }

    /// The part of an MCP tool name after its namespace prefix, or nil when this
    /// is not an MCP tool.
    ///
    /// TWO prefixes, deliberately. `mcp__<server>__<tool>` is the wire spelling
    /// providers use (see `ClaudeProvider`'s inbound conversion), while
    /// `mcp/<server>/<tool>` is what `MCPToolAdapter.name` produces and what the
    /// registry and transcript actually carry. Only the first was matched here,
    /// so every real MCP tool fell through to the wrench + a mangled label —
    /// latent until Git Mage's tools moved onto this path.
    private static func mcpRemainder(_ name: String) -> String? {
        if name.hasPrefix("mcp__") { return String(name.dropFirst(5)) }
        if name.hasPrefix("mcp/") { return String(name.dropFirst(4)) }
        return nil
    }

    private static func iconAndTint(for name: String) -> (String, ToolTint) {
        if mcpRemainder(name) != nil {
            // Presentation-only affordance, NOT a capability coupling: git is by
            // far the most-used MCP family, and a generic puzzle piece on every
            // commit/push/checkout reads worse than the branch glyph these calls
            // carried when they were the host's own `git_op`. An unrecognised
            // server still gets the puzzle piece.
            if name.hasPrefix("mcp/gitmage/") || name.hasPrefix("mcp__gitmage__") {
                return ("arrow.triangle.branch", .secondary)
            }
            return ("puzzlepiece.extension", .secondary)
        }
        switch name {
        case "run_terminal": return ("terminal", .secondary)
        case "run_tool_script": return ("curlybraces", .secondary)
        case "workspace_control": return ("macwindow", .secondary)
        case "edit_file": return ("pencil", .primary)
        case "read_file": return ("doc.text", .secondary)
        case "memory_write": return ("brain", .primary)
        case "memory_search": return ("brain.head.profile", .secondary)
        case "scry_render": return ("paintpalette", .secondary)
        case "spawn_subagent": return ("person.2", .secondary)
        case "use_skill": return ("wand.and.stars", .secondary)
        case "propose_skill": return ("lightbulb", .secondary)
        default: return ("wrench.and.screwdriver", .secondary)
        }
    }
}
