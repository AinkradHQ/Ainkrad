import Foundation
import Security

enum ImportError: Error, Equatable { case fileAbsent, missingInferenceScope, malformed }

/// Reads the Claude Code CLI's own OAuth login and returns an `OAuthToken`.
///
/// Claude Code stores its credentials in one of two places depending on version:
/// the file `~/.claude/.credentials.json`, or the macOS Keychain (generic-password
/// item, service `"Claude Code-credentials"`). Both hold the same
/// `{"claudeAiOauth":{...}}` JSON shape, so a single `decode(_:)` handles either.
///
/// The file is read first (no prompt); the Keychain is the fallback. Reading the
/// Keychain item's DATA can raise a one-time macOS access prompt (the item is
/// owned by Claude Code) — but a mere existence check reads attributes only and
/// never prompts, so `isAvailable` is prompt-free. The app is non-sandboxed, so
/// both reads are permitted.
struct ClaudeCodeCredentialImporter {
    static let keychainService = "Claude Code-credentials"

    private let path: URL
    private let service: String
    // Seams — default to real file/Keychain access; overridable in tests.
    private let readFile: (URL) -> Data?
    private let readKeychainData: (String) -> Data?
    private let keychainItemExists: (String) -> Bool

    init(
        path: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json"),
        service: String = ClaudeCodeCredentialImporter.keychainService,
        readFile: @escaping (URL) -> Data? = {
            FileManager.default.fileExists(atPath: $0.path) ? try? Data(contentsOf: $0) : nil
        },
        readKeychainData: @escaping (String) -> Data? = ClaudeCodeCredentialImporter.keychainData,
        keychainItemExists: @escaping (String) -> Bool = ClaudeCodeCredentialImporter.keychainExists
    ) {
        self.path = path
        self.service = service
        self.readFile = readFile
        self.readKeychainData = readKeychainData
        self.keychainItemExists = keychainItemExists
    }

    /// True when a Claude Code login exists in either source. Prompt-free: the
    /// Keychain check reads attributes only, never the secret data.
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: path.path) || keychainItemExists(service)
    }

    /// Loads the token, preferring the file (no prompt) and falling back to the
    /// Keychain (may raise a one-time access prompt).
    func load() throws -> OAuthToken {
        if let data = readFile(path) { return try Self.decode(data) }
        if let data = readKeychainData(service) { return try Self.decode(data) }
        throw ImportError.fileAbsent
    }

    static func decode(_ data: Data) throws -> OAuthToken {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let access = oauth["accessToken"] as? String,
            let refresh = oauth["refreshToken"] as? String
        else {
            throw ImportError.malformed
        }
        let scopes = (oauth["scopes"] as? [String]) ?? []
        guard scopes.contains("user:inference") else { throw ImportError.missingInferenceScope }
        // Claude Code stores expiresAt in milliseconds.
        let expiresMS = (oauth["expiresAt"] as? Double) ?? 0
        return OAuthToken(
            accessToken: access, refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresMS / 1000),
            scopes: scopes)
    }

    // MARK: - Keychain (real access)

    /// Existence check — attributes only, so it never triggers an access prompt.
    static func keychainExists(_ service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the item's secret data. May raise a one-time macOS access prompt
    /// because the item is owned by Claude Code; returns nil if denied/absent.
    static func keychainData(_ service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return data
    }
}
