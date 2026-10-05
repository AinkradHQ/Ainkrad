import AinkradHostRuntime
import Foundation

/// Keyless `web_search` backend that scrapes DuckDuckGo's no-JS HTML endpoint
/// (`https://html.duckduckgo.com/html/`). No API key, no account, no payment
/// card — always `isConfigured`. The trade-off is fragility: this parses HTML,
/// so a markup change on DuckDuckGo's side can break result extraction (falls
/// back to an empty, non-error result). Parsing is isolated in `parse(_:)` so
/// it can be unit-tested against a captured fixture.
struct DuckDuckGoSearchBackend: WebSearchBackend {
    let http: DataHTTPClient

    /// No credential to configure — the whole point of this backend.
    var isConfigured: Bool { true }

    func search(query: String, count: Int) async throws -> [WebSearchResult] {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [.init(name: "q", value: query)]
        var request = URLRequest(url: comps.url!, timeoutInterval: 20)
        // DuckDuckGo serves an empty page to clients without a browser UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("web_search got HTTP \(response.statusCode) from DuckDuckGo.")
        }
        let html = String(decoding: data, as: UTF8.self)
        return Array(Self.parse(html).prefix(count))
    }

    // MARK: - Parsing (pure, testable)

    /// Extracts result rows from DuckDuckGo's HTML page. Each result is an
    /// `<a class="result__a" href="…">title</a>` anchor; the snippet is the
    /// nearest following `<a class="result__snippet">…</a>`. HTML tags are
    /// stripped and entities decoded. Redirect hrefs (`/l/?uddg=<encoded>`) are
    /// unwrapped to the real destination URL.
    static func parse(_ html: String) -> [WebSearchResult] {
        let anchorPattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>"#
        let anchors = matches(anchorPattern, in: html)
        let snippets = matches(snippetPattern, in: html)
        var out: [WebSearchResult] = []
        for (i, a) in anchors.enumerated() {
            let url = unwrapRedirect(a.0)
            guard !url.isEmpty else { continue }
            let title = stripHTML(a.1)
            let snippet = i < snippets.count ? stripHTML(snippets[i].0) : ""
            out.append(WebSearchResult(title: title, url: url, snippet: snippet))
        }
        return out
    }

    /// Returns (group1, group2) for each match; group2 is empty when the pattern
    /// has a single capture group.
    private static func matches(_ pattern: String, in text: String) -> [(String, String)] {
        guard
            let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            let g1 = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
            let g2 =
                m.numberOfRanges > 2 && m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            return (g1, g2)
        }
    }

    /// DuckDuckGo wraps result links as `//duckduckgo.com/l/?uddg=<percent-encoded-url>`.
    /// Pull the real URL out of `uddg`; leave already-absolute links alone.
    private static func unwrapRedirect(_ href: String) -> String {
        var h = href
        if h.hasPrefix("//") { h = "https:" + h }
        guard let comps = URLComponents(string: h),
            let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value
        else { return decodeEntities(href.hasPrefix("//") ? "https:" + href : href) }
        return uddg
    }

    /// Strips HTML tags (e.g. `<b>` highlight spans) and decodes entities.
    private static func stripHTML(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&nbsp;": " "]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }
}
