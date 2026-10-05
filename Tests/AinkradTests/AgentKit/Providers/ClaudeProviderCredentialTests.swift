import Foundation
import Testing

@testable import Ainkrad

@Suite struct ClaudeProviderCredentialTests {
    // Static request builder is exposed internal for testing (Task 9 extends it).
    @Test func apiKeyCredentialSetsXApiKeyHeader() {
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "sys", tools: [],
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .apiKey("sk-ant-xyz"))
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-xyz")
        #expect(req.value(forHTTPHeaderField: "authorization") == nil)
    }
}
