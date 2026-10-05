import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillReflectionDirective")
@MainActor
struct SkillReflectionDirectiveTests {
    @Test func directiveNamesProposeSkillAndTheTools() {
        let d = SkillReflectionDirective.build(toolNames: ["edit_file", "git_op"])
        #expect(d.contains("propose_skill"))
        #expect(d.contains("edit_file"))
        #expect(d.contains("git_op"))
    }

    @Test func dismissClearsWithoutSending() {
        let session = TestSessionFactory.make()
        session.updateSkillSuggestion(
            from: [
                AgentMessage(role: .user, text: "ship"),
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
            ], succeeded: true)
        #expect(session.pendingSkillSuggestion != nil)
        session.dismissSkillSuggestion()
        #expect(session.pendingSkillSuggestion == nil)
    }
}
