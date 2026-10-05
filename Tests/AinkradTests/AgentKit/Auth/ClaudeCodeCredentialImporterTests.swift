import Foundation
import Testing

@testable import Ainkrad

@Suite struct ClaudeCodeCredentialImporterTests {
    private func payload(scopes: [String], expiresAt: Int) -> Data {
        let scopeJSON = scopes.map { "\"\($0)\"" }.joined(separator: ",")
        return """
            {"claudeAiOauth":{"accessToken":"AT","refreshToken":"RT",
             "expiresAt":\(expiresAt),"scopes":[\(scopeJSON)]}}
            """.data(using: .utf8)!
    }

    @Test func decodesValidCredentials() throws {
        let token = try ClaudeCodeCredentialImporter.decode(payload(scopes: ["user:inference"], expiresAt: 5000))
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 5))  // ms → s
    }

    @Test func rejectsWhenInferenceScopeMissing() {
        #expect(throws: ImportError.missingInferenceScope) {
            _ = try ClaudeCodeCredentialImporter.decode(payload(scopes: ["user:profile"], expiresAt: 5000))
        }
    }

    @Test func rejectsMalformed() {
        #expect(throws: ImportError.malformed) {
            _ = try ClaudeCodeCredentialImporter.decode(Data("{}".utf8))
        }
    }

    // MARK: - File vs. Keychain source selection (injected seams)

    private let missingURL = URL(fileURLWithPath: "/nonexistent/.credentials.json")

    @Test func loadFallsBackToKeychainWhenFileAbsent() throws {
        let kc = payload(scopes: ["user:inference"], expiresAt: 7000)
        let importer = ClaudeCodeCredentialImporter(
            path: missingURL,
            readFile: { _ in nil },  // no file
            readKeychainData: { _ in kc },  // keychain has it
            keychainItemExists: { _ in true })
        let token = try importer.load()
        #expect(token.accessToken == "AT")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 7))
    }

    @Test func loadPrefersFileOverKeychain() throws {
        let fileData = payload(scopes: ["user:inference"], expiresAt: 1000)
        let importer = ClaudeCodeCredentialImporter(
            path: missingURL,
            readFile: { _ in fileData },
            readKeychainData: { _ in
                Issue.record("keychain must not be read when file present")
                return nil
            },
            keychainItemExists: { _ in true })
        let token = try importer.load()
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1))  // came from the file
    }

    @Test func loadThrowsFileAbsentWhenNeitherSourceHasCredentials() {
        let importer = ClaudeCodeCredentialImporter(
            path: missingURL,
            readFile: { _ in nil },
            readKeychainData: { _ in nil },
            keychainItemExists: { _ in false })
        #expect(throws: ImportError.fileAbsent) { _ = try importer.load() }
    }

    @Test func isAvailableTrueWhenOnlyKeychainItemExists() {
        let importer = ClaudeCodeCredentialImporter(
            path: missingURL,
            readFile: { _ in nil },
            readKeychainData: { _ in nil },
            keychainItemExists: { _ in true })
        #expect(importer.isAvailable == true)
    }
}
