import Testing

@testable import Ainkrad

@Suite("ToolResultLookup")
struct ToolResultLookupTests {
    private func msg(_ role: AgentMessage.Role, _ content: [AgentContentBlock]) -> AgentMessage {
        AgentMessage(role: role, content: content)
    }

    @Test func findsSuccessResultInFollowingMessage() {
        let messages = [
            msg(.assistant, [.toolUse(id: "t1", name: "Read", input: .null)]),
            msg(.user, [.toolResult(toolUseID: "t1", content: "file contents", isError: false)]),
        ]
        let s = ToolResultLookup.summary(forToolUseID: "t1", after: 0, in: messages)
        #expect(s == ToolResultSummary(text: "file contents", isError: false, isPending: false))
    }

    @Test func carriesErrorFlag() {
        let messages = [
            msg(.assistant, [.toolUse(id: "t1", name: "run_terminal", input: .null)]),
            msg(.user, [.toolResult(toolUseID: "t1", content: "command not found", isError: true)]),
        ]
        let s = ToolResultLookup.summary(forToolUseID: "t1", after: 0, in: messages)
        #expect(s.isError == true)
        #expect(s.text == "command not found")
    }

    @Test func pendingWhenNoResultYet() {
        let messages = [
            msg(.assistant, [.toolUse(id: "t1", name: "Read", input: .null)])
        ]
        let s = ToolResultLookup.summary(forToolUseID: "t1", after: 0, in: messages)
        #expect(s.isPending == true)
        #expect(s.isError == false)
    }

    @Test func ignoresNonMatchingToolUseIDs() {
        let messages = [
            msg(.assistant, [.toolUse(id: "t1", name: "Read", input: .null)]),
            msg(.user, [.toolResult(toolUseID: "OTHER", content: "nope", isError: false)]),
        ]
        #expect(ToolResultLookup.summary(forToolUseID: "t1", after: 0, in: messages).isPending == true)
    }
}
