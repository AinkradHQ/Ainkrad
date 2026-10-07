import Foundation
import Testing

@testable import Ainkrad

@Suite struct ConnectionAuthModeTests {
    @Test func legacyRecordWithoutAuthModeDecodesToApiKey() throws {
        let json = """
            {"id":"\(UUID().uuidString)","presetID":"claude","kind":"claude",
             "displayName":"Claude","baseURL":"https://api.anthropic.com",
             "createdAt":0}
            """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Connection.self, from: json)
        #expect(decoded.authMode == .apiKey)
    }

    @Test func subscriptionAuthModeRoundTrips() throws {
        var conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: Date(timeIntervalSince1970: 0))
        conn.authMode = .subscription
        let data = try JSONEncoder().encode(conn)
        let decoded = try JSONDecoder().decode(Connection.self, from: data)
        #expect(decoded.authMode == .subscription)
    }
}
