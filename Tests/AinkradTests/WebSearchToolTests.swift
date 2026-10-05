import Testing

@testable import Ainkrad

@Suite("WebSearchTool")
@MainActor
struct WebSearchToolTests {
    private struct StubBackend: WebSearchBackend {
        let configured: Bool
        let results: [WebSearchResult]
        var isConfigured: Bool { configured }
        func search(query: String, count: Int) async throws -> [WebSearchResult] { results }
    }
    @Test func gracefulWhenNotConfigured() async throws {
        let tool = WebSearchTool(backend: StubBackend(configured: false, results: []))
        let r = try await tool.execute(.object(["query": .string("swift")]))
        #expect(!r.isError)
        #expect(r.content.lowercased().contains("not configured"))
    }
    @Test func formatsResults() async throws {
        let tool = WebSearchTool(
            backend: StubBackend(
                configured: true,
                results: [WebSearchResult(title: "T", url: "https://x", snippet: "S")]))
        let r = try await tool.execute(.object(["query": .string("q")]))
        #expect(r.content.contains("T"))
        #expect(r.content.contains("https://x"))
    }
    @Test func permissionIsRead() {
        #expect(WebSearchTool(backend: StubBackend(configured: true, results: [])).permission == .read)
    }
    /// Out-of-range/NaN `count` must not trap `Int(_:)` — it should clamp and
    /// still return results (model-controlled input; validate at the boundary).
    @Test func outOfRangeCountDoesNotCrash() async throws {
        let tool = WebSearchTool(
            backend: StubBackend(
                configured: true,
                results: [WebSearchResult(title: "T", url: "https://x", snippet: "S")]))
        for bad: Double in [1e300, -5, 0, Double.nan] {
            let r = try await tool.execute(.object(["query": .string("q"), "count": .number(bad)]))
            #expect(!r.isError)
            #expect(r.content.contains("https://x"))
        }
    }
}
