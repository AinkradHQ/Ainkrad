import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ToolHook matcher")
struct ToolHookMatcherTests {
    @Test func exactNameMatches() {
        #expect(ToolHookMatcher.matches(pattern: "edit_file", toolName: "edit_file"))
        #expect(!ToolHookMatcher.matches(pattern: "edit_file", toolName: "read_file"))
    }

    @Test func starMatchesAll() {
        #expect(ToolHookMatcher.matches(pattern: "*", toolName: "run_terminal"))
    }

    @Test func prefixGlobMatches() {
        #expect(ToolHookMatcher.matches(pattern: "mcp/*", toolName: "mcp/github/create_pr"))
        #expect(!ToolHookMatcher.matches(pattern: "mcp/*", toolName: "edit_file"))
    }

    @Test func documentRoundTrips() {
        let store = InMemoryPersistenceStore()
        let hook = ToolHook(
            id: UUID(), enabled: true, event: .postToolUse,
            match: "edit_file", command: "swiftformat \"$AINKRAD_TOOL_PATH\"", timeoutSeconds: 30)
        store.save(ToolHooksDocument(hooks: [hook]))
        let loaded = store.load(ToolHooksDocument.self)
        #expect(loaded?.hooks.first?.command == "swiftformat \"$AINKRAD_TOOL_PATH\"")
        #expect(loaded?.hooks.first?.event == .postToolUse)
    }
}
