import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct TodoTimelineBuilderTests {
    private func todoCall(_ id: String, _ status: String) -> AgentContentBlock {
        .toolUse(
            id: id, name: "todo_write",
            input: .object([
                "items": .array([
                    .object(["content": .string("step"), "status": .string(status)])
                ])
            ]))
    }

    @Test func todoWriteBecomesTodoStepNotToolStep() {
        let msgs = [
            AgentMessage(role: .user, text: "plan it"),
            AgentMessage(role: .assistant, content: [todoCall("t1", "pending")]),
            AgentMessage(role: .user, content: [.toolResult(toolUseID: "t1", content: "ok", isError: false)]),
        ]
        guard case .agentTurn(_, let steps) = TranscriptTimelineBuilder.build(from: msgs)[1] else {
            Issue.record("expected agent turn")
            return
        }
        #expect(steps.count == 1)
        guard case .todo(let items) = steps[0].kind else {
            Issue.record("not a todo step")
            return
        }
        #expect(items == [TodoItem(content: "step", status: .pending)])
    }

    @Test func repeatedTodoWriteCollapsesToLatest() {
        let msgs = [
            AgentMessage(role: .user, text: "go"),
            AgentMessage(role: .assistant, content: [todoCall("t1", "pending"), .text("working")]),
            AgentMessage(role: .assistant, content: [todoCall("t2", "completed")]),
        ]
        guard case .agentTurn(_, let steps) = TranscriptTimelineBuilder.build(from: msgs)[1] else {
            Issue.record("expected agent turn")
            return
        }
        let todoSteps = steps.compactMap { step -> [TodoItem]? in
            if case .todo(let items) = step.kind { return items } else { return nil }
        }
        #expect(todoSteps.count == 1)  // only the latest survives
        #expect(todoSteps[0] == [TodoItem(content: "step", status: .completed)])
    }
}
