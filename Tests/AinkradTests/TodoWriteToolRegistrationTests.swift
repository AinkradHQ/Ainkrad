import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("TodoWriteToolRegistration")
@MainActor
struct TodoWriteToolRegistrationTests {
    @Test func registryExposesTodoWrite() {
        let registry = AgentToolRegistry(tools: [ReadFileTool(), TodoWriteTool()])
        #expect(registry.tool(named: "todo_write") != nil)
        #expect(registry.schemas.contains { $0.name == "todo_write" })
    }
}
