import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MediaKeyedBackends")
struct MediaKeyedBackendsTests {
    private struct JSONHTTP: DataHTTPClient {
        let json: String
        let status: Int
        init(json: String, status: Int = 200) {
            self.json = json
            self.status = status
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }
    /// Routes by host: JSON for the Replicate API, raw bytes for the image CDN.
    private struct TwoHopHTTP: DataHTTPClient {
        let apiJSON: String
        let imageBytes: [UInt8]
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let host = request.url?.host ?? ""
            let (body, status): (Data, Int) =
                host.contains("replicate.com")
                ? (Data(apiJSON.utf8), 200)
                : (Data(imageBytes), 200)
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func keyed(_ secretID: String) -> InMemorySecretStore {
        let s = InMemorySecretStore()
        s.setSecret("k", for: secretID)
        return s
    }
    private let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    // MARK: Stability

    @Test func stabilityConfigAndDecode() async throws {
        #expect(StabilityImageBackend(secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}")).isConfigured == false)
        let backend = StabilityImageBackend(
            secrets: keyed(StabilityImageBackend.secretID),
            http: JSONHTTP(json: #"{"artifacts":[{"base64":"QUJD"}]}"#))
        #expect(backend.isConfigured)
        #expect(try await backend.generateImage(prompt: "x").base64 == "QUJD")
    }

    @Test func stabilityErrorThrows() async {
        let backend = StabilityImageBackend(
            secrets: keyed(StabilityImageBackend.secretID), http: JSONHTTP(json: "e", status: 401))
        await #expect(throws: ToolError.self) { _ = try await backend.generateImage(prompt: "x") }
    }

    // MARK: Google Imagen

    @Test func googleConfigAndDecode() async throws {
        #expect(GoogleImagenBackend(secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}")).isConfigured == false)
        let b64 = Data(pngBytes).base64EncodedString()
        let backend = GoogleImagenBackend(
            secrets: keyed(GoogleImagenBackend.secretID),
            http: JSONHTTP(json: #"{"predictions":[{"bytesBase64Encoded":"\#(b64)"}]}"#))
        let img = try await backend.generateImage(prompt: "x")
        #expect(img.base64 == b64)
        #expect(img.mediaType == "image/png")
    }

    // MARK: Hugging Face

    @Test func huggingFaceConfigAndRawBytes() async throws {
        #expect(
            HuggingFaceImageBackend(secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}")).isConfigured == false)
        let backend = HuggingFaceImageBackend(
            secrets: keyed(HuggingFaceImageBackend.secretID),
            http: BytesStub(bytes: pngBytes))
        let img = try await backend.generateImage(prompt: "x")
        #expect(img.base64 == Data(pngBytes).base64EncodedString())
        #expect(img.mediaType == "image/png")
    }

    private struct BytesStub: DataHTTPClient {
        let bytes: [UInt8]
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(bytes), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    // MARK: Replicate

    @Test func replicateParsesOutputStringOrArray() {
        #expect(
            ReplicateImageBackend.firstOutputURL(in: Data(#"{"output":"https://cdn/x.png"}"#.utf8))
                == "https://cdn/x.png")
        #expect(
            ReplicateImageBackend.firstOutputURL(
                in: Data(#"{"output":["https://cdn/a.png","https://cdn/b.png"]}"#.utf8)) == "https://cdn/a.png")
        #expect(ReplicateImageBackend.firstOutputURL(in: Data(#"{"output":null}"#.utf8)) == nil)
    }

    @Test func replicateTwoHopDownloadsImage() async throws {
        let backend = ReplicateImageBackend(
            secrets: keyed(ReplicateImageBackend.secretID),
            http: TwoHopHTTP(apiJSON: #"{"output":["https://cdn.example/x.png"]}"#, imageBytes: pngBytes))
        let img = try await backend.generateImage(prompt: "x")
        #expect(img.base64 == Data(pngBytes).base64EncodedString())
        #expect(img.mediaType == "image/png")
    }

    @Test func replicateNotConfiguredWithoutKey() {
        #expect(ReplicateImageBackend(secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}")).isConfigured == false)
    }
}
