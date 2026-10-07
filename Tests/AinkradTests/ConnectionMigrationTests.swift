import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Connection migration")
struct ConnectionMigrationTests {
    /// Decodes through the same `JSONDecoder` configuration production uses
    /// (`PersistenceCoding.decoder`, ISO-8601 dates) so this test exercises the
    /// real on-disk decode path, not a laxer default decoder.
    private func decode(_ json: String) throws -> Connection {
        try PersistenceCoding.decoder.decode(Connection.self, from: Data(json.utf8))
    }

    @Test("legacy openai connection migrates to OpenAI-compatible preset")
    func legacyOpenAI() throws {
        let c = try decode(
            """
            {"id":"\(UUID().uuidString)","provider":"openai","displayName":"OpenAI Key","createdAt":"2024-01-01T00:00:00Z"}
            """)
        #expect(c.presetID == "openai")
        #expect(c.kind == .openAICompatible)
        #expect(c.baseURL == "https://api.openai.com/v1")
    }

    @Test("legacy claude connection migrates to claude preset")
    func legacyClaude() throws {
        let c = try decode(
            """
            {"id":"\(UUID().uuidString)","provider":"claude","displayName":"Claude Key","createdAt":"2024-01-01T00:00:00Z"}
            """)
        #expect(c.presetID == "claude")
        #expect(c.kind == .claude)
    }

    @Test("new-format connection decodes as-is")
    func newFormat() throws {
        let c = try decode(
            """
            {"id":"\(UUID().uuidString)","presetID":"groq","kind":"openAICompatible","displayName":"Groq","baseURL":"https://api.groq.com/openai/v1","createdAt":"2024-01-01T00:00:00Z"}
            """)
        #expect(c.presetID == "groq")
        #expect(c.baseURL == "https://api.groq.com/openai/v1")
    }
}
