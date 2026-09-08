import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

@Suite("ImageGenerateTool")
@MainActor
struct ImageGenerateToolTests {
    private struct StubBackend: MediaBackend {
        let configured: Bool
        var isConfigured: Bool { configured }
        func generateImage(prompt: String) async throws -> GeneratedImage {
            GeneratedImage(mediaType: "image/png", base64: "QUJD")
        }
    }
    private func make(configured: Bool) -> (ImageGenerateTool, ScryStore) {
        let store = ScryStore(sessionID: "s")
        return (ImageGenerateTool(backend: StubBackend(configured: configured), store: store), store)
    }
    @Test func addsImageCanvasElement() async throws {
        let (tool, store) = make(configured: true)
        let r = try await tool.execute(.object(["prompt": .string("a cat")]))
        #expect(!r.isError)
        #expect(store.model.elements.first?.kind == .image)
        #expect(store.model.elements.first?.body.hasPrefix("data:image/png;base64,") == true)
    }
    @Test func gracefulWhenNotConfigured() async throws {
        let (tool, store) = make(configured: false)
        let r = try await tool.execute(.object(["prompt": .string("a cat")]))
        #expect(!r.isError)
        #expect(r.content.lowercased().contains("not configured"))
        #expect(store.model.elements.isEmpty)
    }
    @Test func requiresPrompt() async {
        let (tool, _) = make(configured: true)
        await #expect(throws: ToolError.self) { _ = try await tool.execute(.object([:])) }
    }
    @Test func permissionIsReadAndReversible() {
        let (tool, _) = make(configured: true)
        #expect(tool.permission == .read)
        #expect(tool.isIrreversible(.object([:])) == false)
    }
    @Test("a generated image card asks for medium room and is auto-placed")
    func generatedImageUsesSizeHint() async throws {
        let (tool, store) = make(configured: true)
        _ = try await tool.execute(.object(["prompt": .string("a cat")]))
        let e = try #require(store.model.elements.first)
        #expect(e.kind == .image)
        #expect(e.sizeHint == .medium)
    }
}
