import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@Suite("VideoGenerateTool")
@MainActor
struct VideoGenerateToolTests {
    private struct StubBackend: VideoBackend {
        let configured: Bool
        var isConfigured: Bool { configured }
        func generateVideo(prompt: String) async throws -> GeneratedVideo {
            GeneratedVideo(data: Data([1, 2, 3, 4]), fileExtension: "mp4")
        }
    }

    private func tempStore() -> GeneratedMediaStore {
        GeneratedMediaStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ainkrad-test-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func gracefulWhenNotConfigured() async throws {
        let canvas = ScryStore(sessionID: "s")
        let tool = VideoGenerateTool(backend: StubBackend(configured: false), store: canvas, mediaStore: tempStore())
        let result = try await tool.execute(.object(["prompt": .string("a wave")]))
        #expect(result.isError == false)
        #expect(result.content.contains("not configured"))
        #expect(canvas.model.elements.isEmpty)
    }

    @Test func rendersVideoElementAndWritesFile() async throws {
        let canvas = ScryStore(sessionID: "s")
        let tool = VideoGenerateTool(backend: StubBackend(configured: true), store: canvas, mediaStore: tempStore())
        _ = try await tool.execute(.object(["prompt": .string("a wave")]))
        let element = try #require(canvas.model.elements.first)
        #expect(element.kind == .video)
        let url = try #require(URL(string: element.body))
        #expect(url.isFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func requiresPrompt() async {
        let canvas = ScryStore(sessionID: "s")
        let tool = VideoGenerateTool(backend: StubBackend(configured: true), store: canvas, mediaStore: tempStore())
        await #expect(throws: ToolError.self) { _ = try await tool.execute(.object(["prompt": .string("")])) }
    }

    @Test func isReadClassAndReversible() {
        let canvas = ScryStore(sessionID: "s")
        let tool = VideoGenerateTool(backend: StubBackend(configured: true), store: canvas, mediaStore: tempStore())
        #expect(tool.permission == .read)
        #expect(tool.isIrreversible(.object([:])) == false)
    }

    @Test("a generated video card asks for large room and is auto-placed")
    func generatedVideoUsesSizeHint() async throws {
        let canvas = ScryStore(sessionID: "s")
        let tool = VideoGenerateTool(backend: StubBackend(configured: true), store: canvas, mediaStore: tempStore())
        _ = try await tool.execute(.object(["prompt": .string("a wave")]))
        let e = try #require(canvas.model.elements.first)
        #expect(e.kind == .video)
        #expect(e.sizeHint == .large)
    }
}

@Suite("RoutingVideoBackend")
struct RoutingVideoBackendTests {
    private struct TwoHopHTTP: DataHTTPClient {
        let apiJSON: String
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let host = request.url?.host ?? ""
            let body = host.contains("replicate.com") ? Data(apiJSON.utf8) : Data([9, 9, 9])
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    private func router(_ p: PersistenceStore) -> RoutingVideoBackend {
        let secrets = InMemorySecretStore()
        secrets.setSecret("k", for: ReplicateVideoBackend.secretID)
        return RoutingVideoBackend(
            persistence: p,
            secrets: secrets,
            replicate: ReplicateVideoBackend(secrets: secrets, http: TwoHopHTTP(apiJSON: #"{"output":"https://cdn/x.mp4"}"#)),
            luma: LumaVideoBackend(secrets: InMemorySecretStore(), http: TwoHopHTTP(apiJSON: "{}")),
            fal: FalVideoBackend(secrets: InMemorySecretStore(), http: TwoHopHTTP(apiJSON: "{}")),
            auxHTTP: TwoHopHTTP(apiJSON: "{}"))
    }

    @Test func defaultsToReplicateConfigured() async throws {
        let r = router(InMemoryPersistenceStore())
        #expect(r.isConfigured) // replicate keyed
        #expect(try await r.generateVideo(prompt: "x").data == Data([9, 9, 9]))
    }

    @Test func routesToLumaUnconfiguredWithoutKey() {
        let p = InMemoryPersistenceStore()
        p.save(VideoSettingsDocument(provider: "luma"))
        #expect(router(p).isConfigured == false) // luma has no key in this fixture
    }
}

@Suite("VideoSettingsStore")
@MainActor
struct VideoSettingsStoreTests {
    @Test func persistsProvider() {
        let p = InMemoryPersistenceStore()
        VideoSettingsStore(persistence: p).setProvider("fal")
        #expect(VideoSettingsStore(persistence: p).document.provider == "fal")
    }
}
