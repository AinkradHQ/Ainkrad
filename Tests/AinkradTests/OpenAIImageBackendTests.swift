import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("OpenAIImageBackend")
struct OpenAIImageBackendTests {
    private struct StubHTTP: DataHTTPClient {
        let json: String
        let status: Int
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }
    @Test func notConfiguredWithoutKey() {
        let backend = OpenAIImageBackend(secrets: InMemorySecretStore(), http: StubHTTP(json: "{}", status: 200))
        #expect(backend.isConfigured == false)
    }
    @Test func decodesBase64Image() async throws {
        let secrets = InMemorySecretStore()
        secrets.setSecret("sk-test", for: OpenAIImageBackend.secretID)
        let backend = OpenAIImageBackend(
            secrets: secrets,
            http: StubHTTP(json: #"{"data":[{"b64_json":"QUJD"}]}"#, status: 200))
        let img = try await backend.generateImage(prompt: "a cat")
        #expect(img.base64 == "QUJD")
        #expect(img.mediaType == "image/png")
    }
    @Test func non2xxThrows() async {
        let secrets = InMemorySecretStore()
        secrets.setSecret("sk-test", for: OpenAIImageBackend.secretID)
        let backend = OpenAIImageBackend(secrets: secrets, http: StubHTTP(json: "err", status: 401))
        await #expect(throws: ToolError.self) { _ = try await backend.generateImage(prompt: "x") }
    }
}
