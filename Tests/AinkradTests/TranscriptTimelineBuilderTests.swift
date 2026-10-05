import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct TranscriptTimelineBuilderTests {
    @Test func emptyProducesNothing() {
        #expect(TranscriptTimelineBuilder.build(from: []).isEmpty)
    }

    @Test func userThenAssistantTextSplits() {
        let msgs = [
            AgentMessage(role: .user, text: "hi"),
            AgentMessage(role: .assistant, content: [.thinking("r"), .text("hello")]),
        ]
        let items = TranscriptTimelineBuilder.build(from: msgs)
        #expect(items.count == 2)
        guard case .userBubble = items[0] else {
            Issue.record("expected user bubble")
            return
        }
        guard case .agentTurn(_, let steps) = items[1] else {
            Issue.record("expected agent turn")
            return
        }
        #expect(steps.count == 2)
        if case .thinking("r") = steps[0].kind {} else { Issue.record("step0 not thinking") }
        if case .text("hello") = steps[1].kind {} else { Issue.record("step1 not text") }
        #expect(steps.allSatisfy { $0.status == .done })
    }

    @Test func toolLoopCoalescesIntoOneTurn() {
        let msgs = [
            AgentMessage(role: .user, text: "read it"),
            AgentMessage(
                role: .assistant,
                content: [
                    .text("reading"), .toolUse(id: "t1", name: "read_file", input: .object([:])),
                ]),
            AgentMessage(
                role: .user,
                content: [
                    .toolResult(toolUseID: "t1", content: "file body", isError: false)
                ]),
            AgentMessage(role: .assistant, content: [.text("done")]),
        ]
        let items = TranscriptTimelineBuilder.build(from: msgs)
        #expect(items.count == 2)  // ONE user bubble + ONE coalesced agent turn
        guard case .agentTurn(_, let steps) = items[1] else {
            Issue.record("expected agent turn")
            return
        }
        #expect(steps.count == 3)  // text, tool(done), text
        guard case .tool(let payload) = steps[1].kind else {
            Issue.record("step1 not tool")
            return
        }
        #expect(payload.result.text == "file body")
        #expect(steps[1].status == .done)
    }

    @Test func pendingToolIsRunning() {
        let msgs = [
            AgentMessage(role: .user, text: "go"),
            AgentMessage(
                role: .assistant,
                content: [
                    .toolUse(id: "t1", name: "read_file", input: .object([:]))
                ]),
        ]
        let items = TranscriptTimelineBuilder.build(from: msgs)
        guard case .agentTurn(_, let steps) = items[1] else {
            Issue.record("expected agent turn")
            return
        }
        #expect(steps[0].status == .running)
    }

    @Test func erroredToolIsError() {
        let msgs = [
            AgentMessage(role: .user, text: "go"),
            AgentMessage(
                role: .assistant,
                content: [
                    .toolUse(id: "t1", name: "read_file", input: .object([:]))
                ]),
            AgentMessage(
                role: .user,
                content: [
                    .toolResult(toolUseID: "t1", content: "boom", isError: true)
                ]),
        ]
        let items = TranscriptTimelineBuilder.build(from: msgs)
        guard case .agentTurn(_, let steps) = items[1] else {
            Issue.record("expected agent turn")
            return
        }
        #expect(steps[0].status == .error)
    }

    @Test func twoPromptsProduceTwoTurns() {
        let msgs = [
            AgentMessage(role: .user, text: "one"),
            AgentMessage(role: .assistant, text: "a"),
            AgentMessage(role: .user, text: "two"),
            AgentMessage(role: .assistant, text: "b"),
        ]
        let items = TranscriptTimelineBuilder.build(from: msgs)
        #expect(items.count == 4)
    }
}
