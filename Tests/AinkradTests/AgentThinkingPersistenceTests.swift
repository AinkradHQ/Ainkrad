import AinkradHostRuntime
// Tests/AinkradTests/AgentThinkingPersistenceTests.swift
import Foundation
import Testing

@testable import Ainkrad

@MainActor
private final class ThinkingScriptedProvider: LLMProvider {
    var turns: [[AgentEvent]]
    init(_ turns: [[AgentEvent]]) { self.turns = turns }
    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let batch = turns.isEmpty ? [] : turns.removeFirst()
        return AsyncThrowingStream { cont in
            for e in batch { cont.yield(e) }
            cont.finish()
        }
    }
}

@MainActor
@Suite struct AgentThinkingPersistenceTests {
    @Test func thinkingPersistedOnToollessTurn() async {
        let provider = ThinkingScriptedProvider([
            [
                .thinkingDelta("step one, "), .thinkingDelta("step two"),
                .textDelta("the answer"), .done(stopReason: "end_turn"),
            ]
        ])
        let session = TestSessionFactory.make(provider: provider)
        session.send("hi")
        await session.currentTask?.value

        let assistant = session.messages.last!
        #expect(assistant.role == .assistant)
        #expect(assistant.thinkingText == "step one, step two")
        #expect(assistant.text == "the answer")
        // Thinking leads the block list.
        if case .thinking = assistant.content.first {} else { Issue.record("thinking not leading") }
    }

    @Test func thinkingPersistedOnToolTurn() async {
        let provider = ThinkingScriptedProvider([
            [
                .thinkingDelta("must read file"),
                .toolUseComplete(id: "1", name: "read_file", input: .object(["path": .string("/etc/hosts")])),
                .done(stopReason: "tool_use"),
            ],
            [.textDelta("done"), .done(stopReason: "end_turn")],
        ])
        // `.fullAuto` so the `.read` tool auto-approves without parking on the
        // approval gate. In `.autoApprove` a read still requires approval when
        // `gateReads` is on (the store default), which would park the turn on
        // the approval continuation and hang `currentTask.value` forever.
        let session = TestSessionFactory.make(provider: provider, mode: .fullAuto)
        session.send("read it")
        await session.currentTask?.value

        // The assistant tool-call message (first assistant turn) carries the thinking.
        let toolTurn = session.messages.first { m in
            m.role == .assistant && m.content.contains { if case .toolUse = $0 { return true } else { return false } }
        }!
        #expect(toolTurn.thinkingText == "must read file")
    }
}
