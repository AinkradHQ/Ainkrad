import Foundation

/// Export format for a rendered conversation transcript.
enum ExportFormat { case markdown, html }

/// Renders a conversation to markdown or HTML, with optional secret redaction.
///
/// Kept as a standalone, side-effect-free serializer (rather than folded into a
/// view model) so a future hosted-share path can reuse it verbatim.
enum ConversationExporter {
    static func export(
        _ messages: [AgentMessage], format: ExportFormat,
        title: String = "Conversation", redactions: [String] = []
    ) -> String {
        switch format {
        case .markdown: return markdown(messages, title: title, redactions: redactions)
        case .html: return html(messages, title: title, redactions: redactions)
        }
    }

    private static func redact(_ s: String, _ redactions: [String]) -> String {
        redactions.reduce(s) { $0.replacingOccurrences(of: $1, with: "[redacted]") }
    }

    private static func markdown(_ messages: [AgentMessage], title: String, redactions: [String]) -> String {
        var out = "# \(title)\n\n"
        for m in messages {
            out += "**\(m.role == .user ? "User" : "Sage")**\n\n"
            for block in m.content {
                switch block {
                case .text(let t): out += redact(t, redactions) + "\n\n"
                case .toolUse(_, let name, _): out += "```tool: \(name)\n```\n\n"
                case .toolResult(_, let content, _): out += "```result\n\(redact(content, redactions))\n```\n\n"
                case .image: out += "_[image]_\n\n"
                case .thinking: break  // display-only scaffolding — omit from exports
                }
            }
        }
        return out
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func html(_ messages: [AgentMessage], title: String, redactions: [String]) -> String {
        var body = ""
        for m in messages {
            body += "<section class=\"\(m.role.rawValue)\"><h3>\(m.role == .user ? "User" : "Sage")</h3>"
            for block in m.content {
                switch block {
                case .text(let t): body += "<p>\(esc(redact(t, redactions)))</p>"
                case .toolUse(_, let name, _): body += "<pre>tool: \(esc(name))</pre>"
                case .toolResult(_, let content, _): body += "<pre>\(esc(redact(content, redactions)))</pre>"
                case .image: body += "<p><em>[image]</em></p>"
                case .thinking: break  // display-only scaffolding — omit from exports
                }
            }
            body += "</section>"
        }
        return
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(esc(title))</title></head><body>\(body)</body></html>"
    }
}
