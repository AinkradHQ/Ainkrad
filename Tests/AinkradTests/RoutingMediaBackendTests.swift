import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("RoutingMediaBackend")
struct RoutingMediaBackendTests {
    /// Returns a fixed payload; each backend is distinguishable by what its HTTP
    /// client is primed to return.
    private struct StubHTTP: DataHTTPClient {
        let payload: String
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (
                Data(payload.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
    }
    private struct BytesHTTP: DataHTTPClient {
        let bytes: [UInt8]
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(bytes), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    private let pngB64 = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).base64EncodedString()

    private func makeRouter(_ persistence: PersistenceStore) -> RoutingMediaBackend {
        let secrets = InMemorySecretStore()
        secrets.setSecret("k", for: OpenAIImageBackend.secretID)
        return RoutingMediaBackend(
            persistence: persistence,
            secrets: secrets,
            openai: OpenAIImageBackend(
                secrets: secrets, http: StubHTTP(payload: #"{"data":[{"b64_json":"T1BFTkFJ"}]}"#)),
            pollinations: PollinationsImageBackend(http: BytesHTTP(bytes: [0xFF, 0xD8, 0xFF, 0xE0])),
            stability: StabilityImageBackend(secrets: secrets, http: StubHTTP(payload: "{}")),
            replicate: ReplicateImageBackend(secrets: secrets, http: StubHTTP(payload: "{}")),
            google: GoogleImagenBackend(secrets: secrets, http: StubHTTP(payload: "{}")),
            huggingface: HuggingFaceImageBackend(secrets: secrets, http: StubHTTP(payload: "{}")),
            auxHTTP: StubHTTP(payload: #"{"images":["\#(pngB64)"]}"#))
    }

    @Test func defaultsToOpenAI() async throws {
        let router = makeRouter(InMemoryPersistenceStore())
        #expect(router.isConfigured)
        let img = try await router.generateImage(prompt: "x")
        #expect(String(data: Data(base64Encoded: img.base64)!, encoding: .utf8) == "OPENAI")
    }

    @Test func routesToKeylessPollinations() async throws {
        let p = InMemoryPersistenceStore()
        p.save(MediaSettingsDocument(provider: "pollinations"))
        let router = makeRouter(p)
        #expect(router.isConfigured)  // Pollinations always configured
        #expect(try await router.generateImage(prompt: "x").mediaType == "image/jpeg")
    }

    @Test func routesToLocalSDWithLiveURL() async throws {
        let p = InMemoryPersistenceStore()
        p.save(MediaSettingsDocument(provider: "localsd", localSDURL: ""))
        var router = makeRouter(p)
        #expect(router.isConfigured == false)  // no URL yet
        p.save(MediaSettingsDocument(provider: "localsd", localSDURL: "http://127.0.0.1:7860"))
        router = makeRouter(p)
        #expect(router.isConfigured)
        #expect(try await router.generateImage(prompt: "x").base64 == pngB64)
    }

    @Test func providerSwitchIsLiveAcrossCalls() async throws {
        let p = InMemoryPersistenceStore()
        let router = makeRouter(p)
        p.save(MediaSettingsDocument(provider: "pollinations"))
        #expect(try await router.generateImage(prompt: "x").mediaType == "image/jpeg")
        p.save(MediaSettingsDocument(provider: "openai"))
        let img = try await router.generateImage(prompt: "x")
        #expect(String(data: Data(base64Encoded: img.base64)!, encoding: .utf8) == "OPENAI")
    }
}
