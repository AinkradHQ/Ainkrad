import Testing

@testable import Ainkrad

@Suite("MediaBackend")
struct MediaBackendTests {
    private struct StubBackend: MediaBackend {
        let configured: Bool
        var isConfigured: Bool { configured }
        func generateImage(prompt: String) async throws -> GeneratedImage {
            GeneratedImage(mediaType: "image/png", base64: "AAAA")
        }
    }
    @Test func reportsConfiguration() {
        #expect(StubBackend(configured: false).isConfigured == false)
    }
    @Test func returnsImage() async throws {
        let img = try await StubBackend(configured: true).generateImage(prompt: "a cat")
        #expect(img == GeneratedImage(mediaType: "image/png", base64: "AAAA"))
    }
}
