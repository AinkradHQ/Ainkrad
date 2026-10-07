import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct AgentThinkingBlockTests {
    @Test func wireContentStripsThinking() {
        let msg = AgentMessage(
            role: .assistant,
            content: [
                .thinking("internal reasoning"),
                .text("visible answer"),
            ])
        #expect(msg.wireContent == [.text("visible answer")])
        #expect(msg.thinkingText == "internal reasoning")
        #expect(msg.text == "visible answer")
    }

    @Test func thinkingRoundTripsThroughCodable() throws {
        let original = AgentMessage(
            role: .assistant,
            content: [
                .thinking("why"), .text("what"),
                .toolUse(id: "t1", name: "read_file", input: .object([:])),
            ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)
        #expect(decoded == original)
    }

    @Test func savedSessionRoundTripsThinking() throws {
        let session = SavedSession(
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            messages: [
                AgentMessage(
                    role: .assistant,
                    content: [.thinking("r"), .text("a")])
            ])
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SavedSession.self, from: data)
        #expect(decoded == session)
    }
}
