import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@Suite("SpeakAudioCard")
@MainActor
struct SpeakAudioCardTests {
    private struct StubProducer: SpeechAudioProducing {
        let data: Data
        let fail: Bool
        func audio(for text: String) async throws -> (data: Data, ext: String) {
            if fail { throw ToolError.message("boom") }
            return (data, "mp3")
        }
    }
    private struct NoopSynth: SpeechSynthesizing { func speak(_ text: String) {} }
    private struct NoopPlayer: AudioPlaying { func play(_ data: Data) {} }

    private func tempStore() -> GeneratedMediaStore {
        GeneratedMediaStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ainkrad-test-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func rendersDownloadableAudioElement() async throws {
        let canvas = ScryStore(sessionID: "s")
        let tool = SpeakTool(synth: NoopSynth(),
                             producer: StubProducer(data: Data([1, 2, 3]), fail: false),
                             store: canvas, mediaStore: tempStore(), player: NoopPlayer())
        _ = try await tool.execute(.object(["text": .string("hello")]))
        let element = try #require(canvas.model.elements.first)
        #expect(element.kind == .audio)
        let url = try #require(URL(string: element.body))
        #expect(url.isFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func fallsBackToPlayWhenProductionFails() async throws {
        let canvas = ScryStore(sessionID: "s")
        let tool = SpeakTool(synth: NoopSynth(),
                             producer: StubProducer(data: Data(), fail: true),
                             store: canvas, mediaStore: tempStore(), player: NoopPlayer())
        let result = try await tool.execute(.object(["text": .string("hello")]))
        #expect(result.isError == false)
        #expect(canvas.model.elements.isEmpty) // no card on fallback
    }

    @Test func noProducerKeepsFireAndForget() async throws {
        let tool = SpeakTool(synth: NoopSynth(), mediaStore: tempStore())
        let result = try await tool.execute(.object(["text": .string("hi")]))
        #expect(result.content.contains("Spoke"))
    }

    @Test func requiresText() async {
        let tool = SpeakTool(synth: NoopSynth(), mediaStore: tempStore())
        await #expect(throws: ToolError.self) { _ = try await tool.execute(.object(["text": .string("")])) }
    }

    @Test func resolvesAudioURLFromResult() {
        let canvas = ScryStore(sessionID: "s")
        let id = canvas.add(ScryElement(id: UUID().uuidString, kind: .audio, title: "Speech", body: "file:///tmp/x.caf"))
        #expect(ToolCallImageLookup.canvasAudioURL(resultText: "audio element \(id)", store: canvas) == "file:///tmp/x.caf")
    }

    @Test("a spoken audio card asks for medium room and is auto-placed")
    func spokenAudioUsesSizeHint() async throws {
        let canvas = ScryStore(sessionID: "s")
        let tool = SpeakTool(synth: NoopSynth(),
                             producer: StubProducer(data: Data([1, 2, 3]), fail: false),
                             store: canvas, mediaStore: tempStore(), player: NoopPlayer())
        _ = try await tool.execute(.object(["text": .string("hello")]))
        let e = try #require(canvas.model.elements.first)
        #expect(e.kind == .audio)
        #expect(e.sizeHint == .medium)
    }
}
