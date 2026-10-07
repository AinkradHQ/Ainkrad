import AinkradHostRuntime
import Testing

@testable import Ainkrad

@MainActor
private struct EchoTool: AgentTool {
    let name = "echo"
    let description = "echoes its text argument"
    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]),
        ])
    }
    let permission: ToolPermissionClass = .read
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let t = input["text"]?.stringValue else { throw ToolError.message("missing text") }
        return ToolResult(content: t, isError: false)
    }
}

@Suite("AgentToolRegistry")
@MainActor
struct AgentToolRegistryTests {
    @Test func resolvesAndRuns() async {
        let reg = AgentToolRegistry(tools: [EchoTool()])
        #expect(reg.tool(named: "echo") != nil)
        let r = await reg.run(ToolCall(id: "1", name: "echo", input: .object(["text": .string("hi")])))
        #expect(r == ToolResult(content: "hi", isError: false))
    }

    @Test func unknownToolIsError() async {
        let reg = AgentToolRegistry(tools: [EchoTool()])
        let r = await reg.run(ToolCall(id: "1", name: "nope", input: .null))
        #expect(r.isError)
    }

    @Test func throwBecomesErrorResult() async {
        let reg = AgentToolRegistry(tools: [EchoTool()])
        let r = await reg.run(ToolCall(id: "1", name: "echo", input: .object([:])))
        #expect(r.isError)
        #expect(r.content.contains("missing text"))
    }

    @Test func schemasExposed() {
        let reg = AgentToolRegistry(tools: [EchoTool()])
        #expect(reg.schemas.map(\.name) == ["echo"])
    }
}
