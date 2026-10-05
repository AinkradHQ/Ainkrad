import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("TodoWriteTool")
@MainActor
struct TodoWriteToolTests {
    @Test func echoesListAndSucceeds() async throws {
        let tool = TodoWriteTool()
        let r = try await tool.execute(
            .object([
                "items": .array([
                    .object(["content": .string("A"), "status": .string("completed")]),
                    .object(["content": .string("B"), "status": .string("in_progress")]),
                ])
            ]))
        #expect(!r.isError)
        #expect(r.content.contains("A"))
        #expect(r.content.contains("B"))
    }

    @Test func permissionIsMemoryClass() {
        #expect(TodoWriteTool().permission == .memory)
    }

    @Test func autoApprovesInAskMode() {
        let decision = AgentPermissionPolicy.decide(
            toolPermission: TodoWriteTool().permission, toolName: "todo_write",
            mode: .ask, allowlist: [], gateReads: true, isIrreversible: false)
        #expect(decision == .autoApprove)  // memory-class is exempt even with gateReads on
    }

    @Test func emptyItemsIsError() async throws {
        let r = try await TodoWriteTool().execute(.object(["items": .array([])]))
        #expect(r.isError)
    }
}
