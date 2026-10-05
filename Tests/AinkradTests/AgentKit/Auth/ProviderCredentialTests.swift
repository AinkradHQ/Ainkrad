import Foundation
import Testing

@testable import Ainkrad

@Suite struct ProviderCredentialTests {
    @Test func oauthTokenIsExpiringWithinSkew() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let token = OAuthToken(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(60), scopes: ["user:inference"])
        #expect(token.isExpiring(now: now, skew: 120) == true)  // expires in 60s, skew 120s
        #expect(token.isExpiring(now: now, skew: 30) == false)  // 60s away, skew 30s
    }

    @Test func oauthTokenRoundTripsThroughCodable() throws {
        let token = OAuthToken(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 5), scopes: ["x"])
        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(OAuthToken.self, from: data)
        #expect(decoded == token)
    }
}
