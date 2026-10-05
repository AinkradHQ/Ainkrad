import AinkradHostRuntime
import Foundation

/// Token-free tint selector so the mapping stays pure and unit-testable; the
/// view resolves it to a real `DesignTokens` color.
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
    /// kept as-is here. Callers that want a bare tool name capitalized even
    /// without an underscore (e.g. Settings' MCP tool list) should use
    /// `titleCasedBareName` instead.
    static func humanize(_ name: String) -> String {
        let base = mcpRemainder(name).map { $0.replacingOccurrences(of: "/", with: "_") } ?? name
        guard base.contains("_") else { return base }
        return titleCase(base)
    }

    /// "reset_hard" → "Reset hard", "status" → "Status". Same snake_case
    /// title-casing `humanize` uses, but applied unconditionally — for bare
    /// tool names (no MCP prefix to strip) where an un-capitalized single word
    /// would read inconsistently next to its underscored siblings. Used by the
    /// Settings → MCP Servers tool list, not the transcript path.
    static func titleCasedBareName(_ name: String) -> String {
        titleCase(name)
    }

    /// Readable label for an MCP *resource*, given its declared name and URI.
    ///
    /// Prefers the publisher's own title — apps already supply a human one
    /// ("Terminal buffer", "Lore vault"), and inventing a label over a good one
    /// would be strictly worse. The fallback matters because
    /// `MCPRPC.decodeResourceList` defaults a missing `name` TO THE URI, so a
    /// naive `titleCasedBareName(descriptor.name)` renders "Terminal://buffer"
    /// for any server that omits the field. In that case the URI's last path
    /// segment is the only human-meaningful part ("terminal://buffer" →
    /// "Buffer"), so that is what gets title-cased.
    static func resourceLabel(name: String, uri: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != uri { return trimmed }
        return uriDerivedLabel(uri) ?? uri
    }

    /// "terminal://buffer" → "Buffer", "app://a/b-c" → "B c". Nil when the URI
    /// has no segment worth showing (e.g. "scheme://"), so the caller can fall
    /// back to the raw URI rather than render an empty label.
    private static func uriDerivedLabel(_ uri: String) -> String? {
        let afterScheme = uri.range(of: "://").map { String(uri[$0.upperBound...]) } ?? uri
        guard
            let segment =
                afterScheme
                .split(separator: "/", omittingEmptySubsequences: true).last
        else { return nil }
        let normalized = segment.replacingOccurrences(of: "-", with: "_")
        guard !normalized.isEmpty else { return nil }
        return titleCase(normalized)
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
