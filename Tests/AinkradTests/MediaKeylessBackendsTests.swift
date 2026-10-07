import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MediaKeylessBackends")
struct MediaKeylessBackendsTests {
    /// Returns raw bytes with a chosen status; records the requested URL.
    private final class Recorder: @unchecked Sendable { var url: URL? }
    private struct BytesHTTP: DataHTTPClient {
        let bytes: [UInt8]
        let status: Int
        let recorder: Recorder?
        init(bytes: [UInt8], status: Int = 200, recorder: Recorder? = nil) {
            self.bytes = bytes
            self.status = status
            self.recorder = recorder
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            recorder?.url = request.url!
            return (
                Data(bytes),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }
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

    private let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]
    private let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]

    // MARK: MediaMime

    @Test func sniffsCommonImageTypes() {
        #expect(MediaMime.sniff(Data(pngBytes)) == "image/png")
        #expect(MediaMime.sniff(Data(jpegBytes)) == "image/jpeg")
        #expect(MediaMime.sniff(Data([0x47, 0x49, 0x46, 0x38])) == "image/gif")
        #expect(MediaMime.sniff(Data([0x00, 0x01, 0x02])) == "image/png")  // unknown → png default
    }

    // MARK: Pollinations

    @Test func pollinationsAlwaysConfigured() {
        #expect(PollinationsImageBackend(http: JSONHTTP(json: "")).isConfigured)
    }

    @Test func pollinationsReturnsSniffedImageAndEncodesPromptPath() async throws {
        let rec = Recorder()
        let backend = PollinationsImageBackend(http: BytesHTTP(bytes: jpegBytes, recorder: rec))
        let img = try await backend.generateImage(prompt: "a red cube")
        #expect(img.mediaType == "image/jpeg")
        #expect(img.base64 == Data(jpegBytes).base64EncodedString())
        #expect(rec.url?.absoluteString.hasPrefix("https://image.pollinations.ai/prompt/") == true)
        #expect(rec.url?.absoluteString.contains("nologo=true") == true)
    }

    @Test func pollinationsHTTPErrorThrows() async {
        let backend = PollinationsImageBackend(http: BytesHTTP(bytes: [], status: 500))
        await #expect(throws: ToolError.self) { _ = try await backend.generateImage(prompt: "x") }
    }

    // MARK: Local Stable Diffusion

    @Test func localSDNotConfiguredWithoutURL() {
        #expect(LocalStableDiffusionBackend(baseURL: "", http: JSONHTTP(json: "{}")).isConfigured == false)
        #expect(LocalStableDiffusionBackend(baseURL: "http://127.0.0.1:7860", http: JSONHTTP(json: "{}")).isConfigured)
    }

    @Test func localSDDecodesFirstImage() async throws {
        let b64 = Data(pngBytes).base64EncodedString()
        let backend = LocalStableDiffusionBackend(
            baseURL: "http://127.0.0.1:7860/",
            http: JSONHTTP(json: #"{"images":["\#(b64)"]}"#))
        let img = try await backend.generateImage(prompt: "a cat")
        #expect(img.base64 == b64)
        #expect(img.mediaType == "image/png")
    }

    @Test func localSDHTTPErrorThrows() async {
        let backend = LocalStableDiffusionBackend(
            baseURL: "http://127.0.0.1:7860", http: JSONHTTP(json: "err", status: 500))
        await #expect(throws: ToolError.self) { _ = try await backend.generateImage(prompt: "x") }
    }
}
