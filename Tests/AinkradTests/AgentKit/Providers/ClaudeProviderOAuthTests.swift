import Foundation
import Testing

@testable import Ainkrad

@Suite struct ClaudeProviderOAuthTests {
    private func body(_ req: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    @Test func oauthSetsBearerBetasUAAndXApp() {
        let token = OAuthToken(
            accessToken: "AT", refreshToken: "RT",
            expiresAt: Date(), scopes: ["user:inference"])
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "SYS", tools: [],
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        #expect(req.value(forHTTPHeaderField: "authorization") == "Bearer AT")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(req.value(forHTTPHeaderField: "x-app") == "cli")
        #expect(req.value(forHTTPHeaderField: "user-agent") == "claude-code/2.1.74")
        let betas = req.value(forHTTPHeaderField: "anthropic-beta") ?? ""
        #expect(betas.contains("claude-code-20250219"))
        #expect(betas.contains("oauth-2025-04-20"))
    }

    @Test func oauthSendsClaudeCodeSystemAsFirstBlockOfAnArray() {
        let token = OAuthToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(), scopes: [])
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "MY SYSTEM", tools: [],
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        // OAuth sends `system` as a block array; the FIRST block must be exactly the
        // Claude Code identity string (verbatim — not concatenated with the user prompt).
        let blocks = body(req)["system"] as? [[String: Any]] ?? []
        #expect(blocks.first?["type"] as? String == "text")
        #expect(blocks.first?["text"] as? String == "You are Claude Code, Anthropic's official CLI for Claude.")
        #expect(blocks.count == 2)
        #expect(blocks.last?["text"] as? String == "MY SYSTEM")
    }

    @Test func oauthRewritesSlashMcpToolNamesToDoubleUnderscore() {
        let tools = [AgentToolSchema(name: "mcp/git/status", description: "d", parameters: .object([:]))]
        let token = OAuthToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(), scopes: [])
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "S", tools: tools,
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        let names = ((body(req)["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        #expect(names == ["mcp__git__status"])
    }

    @Test func oauthEchoedAssistantToolUseUsesWireName() {
        let msgs = [
            AgentMessage(
                role: .assistant,
                content: [.toolUse(id: "t1", name: "mcp/git/status", input: .object([:]))])
        ]
        let token = OAuthToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(), scopes: [])
        let req = ClaudeProvider.makeRequest(
            messages: msgs, system: "S", tools: [],
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        let wire =
            ((body(req)["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?
            .first?["name"] as? String
        #expect(wire == "mcp__git__status")
    }

    @Test func oauthToolNameTransformsRoundTrip() {
        #expect(ClaudeProvider.oauthWireToolName("mcp/git/status") == "mcp__git__status")
        #expect(ClaudeProvider.oauthOriginalToolName("mcp__git__status") == "mcp/git/status")
        // Non-MCP (and built-in) names are untouched in both directions.
        #expect(ClaudeProvider.oauthWireToolName("run_terminal") == "run_terminal")
        #expect(ClaudeProvider.oauthOriginalToolName("run_terminal") == "run_terminal")
    }

    @Test func apiKeyDoesNotRewriteToolNamesOrPrependSystem() {
        let tools = [AgentToolSchema(name: "mcp/git/status", description: "d", parameters: .object([:]))]
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "S", tools: tools,
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .apiKey("k"))
        let names = ((body(req)["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        #expect(names == ["mcp/git/status"])  // unchanged on the API-key path
        #expect((body(req)["system"] as? String) == "S")
    }
}
