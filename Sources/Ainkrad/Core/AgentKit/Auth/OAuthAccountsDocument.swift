import AinkradHostRuntime
import Foundation

enum OAuthSource: String, Codable, Sendable { case freshLogin, claudeCodeImport }

/// Non-secret metadata for a connection's OAuth login. Token VALUES live in the
/// Keychain under `oauthSecretID(connectionID)`; this document is safe to sync/log.
struct OAuthAccount: Codable, Equatable, Sendable {
    var provider: String
    var expiresAt: Date
    var scopes: [String]
    var source: OAuthSource
    var email: String?
    var displayName: String?
}

struct OAuthAccountsDocument: PersistableDocument {
    static let documentID = "oauth-accounts"
    var accountsByConnection: [String: OAuthAccount] = [:]

    init(accountsByConnection: [String: OAuthAccount] = [:]) {
        self.accountsByConnection = accountsByConnection
    }

    private enum CodingKeys: String, CodingKey { case accountsByConnection }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountsByConnection =
            try c.decodeIfPresent(
                [String: OAuthAccount].self,
                forKey: .accountsByConnection) ?? [:]
    }
}

/// Keychain id for a connection's OAuth token blob — reuses the `secretID` seam.
func oauthSecretID(_ connectionID: UUID) -> String {
    "connection.\(connectionID.uuidString).oauth"
}
