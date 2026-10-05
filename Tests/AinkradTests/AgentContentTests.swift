import Testing

@testable import Ainkrad

@Suite("AgentContent")
struct AgentContentTests {
    @Test func textConvenienceInitProducesOneTextBlock() {
        let m = AgentMessage(role: .user, text: "hello")
        #expect(m.content == [.text("hello")])
        #expect(m.text == "hello")
    }

    @Test func textAccessorJoinsOnlyTextBlocks() {
        let m = AgentMessage(
            role: .assistant,
            content: [
                .text("a"),
                .toolUse(id: "t1", name: "read_file", input: .object(["path": .string("/x")])),
                .text("b"),
            ])
        #expect(m.text == "ab")
    }

    @Test func toolResultBlockEquatable() {
        let a = AgentContentBlock.toolResult(toolUseID: "t1", content: "ok", isError: false)
        let b = AgentContentBlock.toolResult(toolUseID: "t1", content: "ok", isError: false)
        #expect(a == b)
    }
}
