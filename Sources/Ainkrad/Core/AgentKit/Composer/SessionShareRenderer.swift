// design-lint: allow-file hex-color,radius-literal export data — the shared HTML page's own stylesheet, not app chrome
import Foundation

/// Renders a session to ONE self-contained HTML document: inline CSS, images
/// embedded as `data:` URIs, `.thinking` omitted, secrets redacted. Standalone
/// and side-effect-free (like `ConversationExporter`) so a future hosted-share
/// path can reuse it verbatim.
enum SessionShareRenderer {
    static func render(_ messages: [AgentMessage], title: String, redactions: [String]) -> String {
        // The title is derived from the first user message downstream, so it is
        // just as secret-bearing as any turn text — redact it too before escaping.
        let safeTitle = esc(redact(title, redactions))
        var body = ""
        for m in messages {
            let who = m.role == .user ? "User" : "Sage"
            body += "<section class=\"turn \(m.role.rawValue)\"><h3>\(esc(who))</h3>"
            for block in m.content {
                switch block {
                case .text(let t):
                    body += "<p>\(esc(redact(t, redactions)))</p>"
                case .toolUse(_, let name, _):
                    body += "<pre class=\"tool\">tool: \(esc(name))</pre>"
                case .toolResult(_, let content, _):
                    body += "<pre class=\"result\">\(esc(redact(content, redactions)))</pre>"
                case .image(let mediaType, let base64):
                    body += "<img alt=\"attachment\" src=\"data:\(esc(mediaType));base64,\(base64)\"/>"
                case .thinking:
                    break  // display-only scaffolding — never leaves the app
                }
            }
            body += "</section>"
        }
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(safeTitle)</title>"
            + "<style>\(css)</style></head><body><h1>\(safeTitle)</h1>\(body)</body></html>"
    }

    private static let css = """
        body{font-family:-apple-system,system-ui,sans-serif;max-width:820px;margin:32px auto;padding:0 20px;color:#e6e6ea;background:#0f0f13;line-height:1.5}
        h1{font-size:20px}h3{font-size:13px;opacity:.6;margin:0 0 6px;text-transform:uppercase;letter-spacing:.06em}
        .turn{margin:20px 0}.user h3{color:#7fb2ff}.assistant h3{color:#b28bff}
        pre{background:#17171d;padding:10px 12px;border-radius:8px;overflow-x:auto;font-size:12px}
        img{max-width:100%;border-radius:8px;margin:8px 0}
        """

    private static func redact(_ s: String, _ redactions: [String]) -> String {
        RedactionList.apply(redactions, to: s)
    }

    /// Escapes the five HTML-significant characters. `"` and `'` matter because
    /// `mediaType` is interpolated into a double-quoted `src` attribute — without
    /// quote-escaping a crafted media type could break out and inject markup.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
