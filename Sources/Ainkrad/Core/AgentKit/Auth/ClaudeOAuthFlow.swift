import Foundation
import CryptoKit

enum ClaudeOAuthError: Error, Equatable {
    /// Token endpoint returned a non-200. `body` is the response payload — for a
    /// failed OAuth exchange this is an error JSON (`{"error":…,"error_description":…}`),
    /// never a token — captured so the failure is diagnosable instead of opaque.
    case tokenEndpoint(status: Int, body: String)
    case malformedResponse
    case allEndpointsFailed
    /// The response was not an HTTP response at all — a non-http(s) URL, or a
    /// custom `URLProtocol`. Previously a force-cast, so this crashed.
    case nonHTTPResponse
}

/// Transport seam so token exchange/refresh is unit-testable without real HTTP.
protocol OAuthTokenTransport: Sendable {
    func post(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default transport: URLSession.
struct URLSessionTokenTransport: OAuthTokenTransport {
    func post(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            Log.settings.error("OAuth token endpoint returned a non-HTTP response")
            throw ClaudeOAuthError.nonHTTPResponse
        }
        return (data, http)
    }
}

/// PKCE verifier/challenge pair (S256).
struct PKCE {
    let verifier: String
    let challenge: String
    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        // A CSPRNG failure must never silently yield a weak/zero verifier (that would
        // defeat PKCE). It effectively never fails on macOS; crash rather than proceed.
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "PKCE: SecRandomCopyBytes failed (\(status))")
        let verifier = Data(bytes).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Pure OAuth flow for the Anthropic subscription (Claude Code client).
struct ClaudeOAuthFlow {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURI = "http://localhost:53692/callback"
    static let scopes = "org:create_api_key user:profile user:inference"
    static let tokenURLs = [
        URL(string: "https://platform.claude.com/v1/oauth/token")!,
        URL(string: "https://console.anthropic.com/v1/oauth/token")!,
    ]

    private let transport: OAuthTokenTransport
    private let clientVersion: String

    init(transport: OAuthTokenTransport = URLSessionTokenTransport(), clientVersion: String) {
        self.transport = transport
        self.clientVersion = clientVersion
    }

    static func authorizeURL(state: String, challenge: String) -> URL {
        // Build query parameters with proper percent-encoding
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let params: [(String, String)] = [
            ("code", "true"),
            ("client_id", clientID),
            ("response_type", "code"),
            ("redirect_uri", redirectURI),
            ("scope", scopes),
            ("code_challenge", challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
        ]

        let queryString = params.map { key, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: unreserved)!
            return "\(key)=\(encodedValue)"
        }.joined(separator: "&")

        return URL(string: "https://claude.ai/oauth/authorize?\(queryString)")!
    }

    func exchange(code: String, verifier: String, state: String) async throws -> OAuthToken {
        try await postToken(body: [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "state": state,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ], fallbackRefresh: nil)
    }

    func refresh(refreshToken: String) async throws -> OAuthToken {
        try await postToken(body: [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
        ], fallbackRefresh: refreshToken)
    }

    private func postToken(body: [String: String], fallbackRefresh: String?) async throws -> OAuthToken {
        var lastStatus = 0
        var lastBody = ""
        for url in Self.tokenURLs {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.setValue("application/json", forHTTPHeaderField: "accept")
            req.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "user-agent")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await transport.post(req)
            guard resp.statusCode == 200 else {
                lastStatus = resp.statusCode
                // Failure payload is an OAuth error JSON (no token) — keep + log it.
                lastBody = String(data: data, encoding: .utf8) ?? ""
                Log.settings.error("OAuth token endpoint \(url.host ?? "?", privacy: .public) → \(resp.statusCode, privacy: .public): \(lastBody, privacy: .public)")
                // Fall through to the fallback host ONLY for host/route-level
                // problems (5xx, 404). An auth/rate response (400/401/403/429)
                // is a definitive answer for THIS single-use code — retrying the
                // other host can't succeed, doubles rate-limit pressure, and risks
                // consuming the code. Stop and report it.
                if resp.statusCode >= 500 || resp.statusCode == 404 { continue }
                throw ClaudeOAuthError.tokenEndpoint(status: resp.statusCode, body: lastBody)
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = obj["access_token"] as? String else {
                throw ClaudeOAuthError.malformedResponse
            }
            let refresh = (obj["refresh_token"] as? String) ?? fallbackRefresh ?? ""
            let expiresIn = (obj["expires_in"] as? Double) ?? 3600
            let scopeStr = (obj["scope"] as? String) ?? Self.scopes
            return OAuthToken(accessToken: access, refreshToken: refresh,
                              expiresAt: Date().addingTimeInterval(expiresIn),
                              scopes: scopeStr.split(separator: " ").map(String.init))
        }
        throw lastStatus == 0 ? ClaudeOAuthError.allEndpointsFailed
                              : ClaudeOAuthError.tokenEndpoint(status: lastStatus, body: lastBody)
    }
}
