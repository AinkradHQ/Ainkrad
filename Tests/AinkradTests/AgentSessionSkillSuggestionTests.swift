import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession skill suggestion")
@MainActor
struct AgentSessionSkillSuggestionTests {
    @Test func eligibleTurnPublishesSuggestion() {
        let session = TestSessionFactory.make()
        let msgs = [
            AgentMessage(role: .user, text: "ship the release"),
            AgentMessage(
                role: .assistant,
                content: [
                    .toolUse(id: "0", name: "edit_file", input: .null),
                    .toolUse(id: "1", name: "run_terminal", input: .null),
                    .toolUse(id: "2", name: "git_op", input: .null),
                ]),
            AgentMessage(
                role: .user,
                content: [
                    .toolResult(toolUseID: "0", content: "ok", isError: false),
                    .toolResult(toolUseID: "1", content: "ok", isError: false),
                    .toolResult(toolUseID: "2", content: "ok", isError: false),
                ]),
            AgentMessage(role: .assistant, text: "done"),
        ]
        session.updateSkillSuggestion(from: msgs, succeeded: true)
        #expect(session.pendingSkillSuggestion?.toolNames == ["edit_file", "run_terminal", "git_op"])
    }

    @Test func trivialTurnClearsSuggestion() {
        let session = TestSessionFactory.make()
        session.updateSkillSuggestion(
            from: [
                AgentMessage(role: .user, text: "hi"),
                AgentMessage(role: .assistant, text: "hello"),
            ], succeeded: true)
        #expect(session.pendingSkillSuggestion == nil)
    }
}
