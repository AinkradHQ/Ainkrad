import Foundation
import Testing

@testable import Ainkrad

@Suite struct OAuthAccountsDocumentTests {
    @Test func decodesMissingMapToEmpty() throws {
        let doc = try JSONDecoder().decode(OAuthAccountsDocument.self, from: Data("{}".utf8))
        #expect(doc.accountsByConnection.isEmpty)
    }

    @Test func roundTripsAccount() throws {
        var doc = OAuthAccountsDocument()
        doc.accountsByConnection["ID"] = OAuthAccount(
            provider: "anthropic", expiresAt: Date(timeIntervalSince1970: 1),
            scopes: ["user:inference"], source: .freshLogin, email: nil, displayName: nil)
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(OAuthAccountsDocument.self, from: data)
        #expect(decoded == doc)
    }

    @Test func secretIDMatchesConnectionSeam() {
        let id = UUID()
        #expect(oauthSecretID(id) == "connection.\(id.uuidString).oauth")
    }
}
