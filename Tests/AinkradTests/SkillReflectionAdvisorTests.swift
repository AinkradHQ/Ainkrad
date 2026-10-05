import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillReflectionAdvisor")
struct SkillReflectionAdvisorTests {
    private func userText(_ s: String) -> AgentMessage { AgentMessage(role: .user, text: s) }
    private func toolTurn(_ names: [String]) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: names.enumerated().map { .toolUse(id: "\($0.0)", name: $0.1, input: .null) })
    }
    private func toolResults(_ errors: [Bool]) -> AgentMessage {
        AgentMessage(
            role: .user,
            content: errors.enumerated().map {
                .toolResult(toolUseID: "\($0.0)", content: "r", isError: $0.1)
            })
    }

    @Test func eligibleWhenEnoughSuccessfulToolCalls() {
        let msgs = [
            userText("build the release"),
            toolTurn(["edit_file", "run_terminal", "git_op"]),
            toolResults([false, false, false]),
            AgentMessage(role: .assistant, text: "done"),
        ]
        #expect(
            SkillReflectionAdvisor.evaluate(msgs, succeeded: true)
                == .eligible(toolNames: ["edit_file", "run_terminal", "git_op"]))
    }

    @Test func notEligibleWhenTurnFailed() {
        let msgs = [
            userText("x"), toolTurn(["edit_file", "run_terminal", "git_op"]),
            toolResults([false, false, false]),
        ]
        #expect(SkillReflectionAdvisor.evaluate(msgs, succeeded: false) == .notEligible)
    }

    @Test func notEligibleWhenAnyToolErrored() {
        let msgs = [
            userText("x"), toolTurn(["edit_file", "run_terminal", "git_op"]),
            toolResults([false, true, false]),
        ]
        #expect(SkillReflectionAdvisor.evaluate(msgs, succeeded: true) == .notEligible)
    }

    @Test func notEligibleForTrivialTurn() {
        let msgs = [userText("hi"), AgentMessage(role: .assistant, text: "hello")]
        #expect(SkillReflectionAdvisor.evaluate(msgs, succeeded: true) == .notEligible)
    }

    @Test func scopesToLastUserTurnOnly() {
        // An earlier busy turn must not make a later trivial turn eligible.
        let msgs = [
            userText("old task"), toolTurn(["edit_file", "run_terminal", "git_op"]),
            toolResults([false, false, false]), AgentMessage(role: .assistant, text: "done"),
            userText("thanks"), AgentMessage(role: .assistant, text: "welcome"),
        ]
        #expect(SkillReflectionAdvisor.evaluate(msgs, succeeded: true) == .notEligible)
    }
}
