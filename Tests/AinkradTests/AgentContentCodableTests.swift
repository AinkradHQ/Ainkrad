import Foundation
import Testing

@testable import Ainkrad

@Suite struct AgentContentCodableTests {
    private func roundTrip(_ message: AgentMessage) throws -> AgentMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(AgentMessage.self, from: data)
    }

    @Test func roundTripsAllBlockTypes() throws {
        let message = AgentMessage(
            role: .assistant,
            content: [
                .text("hello"),
                .toolUse(id: "t1", name: "read_file", input: .object(["path": .string("/x")])),
                .toolResult(toolUseID: "t1", content: "ok", isError: false),
                .image(mediaType: "image/png", base64: "AAAA"),
            ])
        let decoded = try roundTrip(message)
        #expect(decoded == message)
    }

    @Test func roundTripsUserRole() throws {
        let decoded = try roundTrip(AgentMessage(role: .user, text: "hi"))
        #expect(decoded.role == .user)
        #expect(decoded.text == "hi")
    }
}
