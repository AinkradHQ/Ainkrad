import Foundation
import Testing

@testable import Ainkrad

@Suite("SpeakTool")
@MainActor
struct SpeakToolTests {
    private final class SpyseSynth: SpeechSynthesizing, @unchecked Sendable {
        var spoken: [String] = []
        func speak(_ text: String) { spoken.append(text) }
    }
    private func tempStore() -> GeneratedMediaStore {
        GeneratedMediaStore(
            baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ainkrad-test-\(UUID().uuidString)", isDirectory: true))
    }
    @Test func speaksText() async throws {
        let spy = SpyseSynth()
        let r = try await SpeakTool(synth: spy, mediaStore: tempStore()).execute(.object(["text": .string("hello")]))
        #expect(!r.isError)
        #expect(spy.spoken == ["hello"])
    }
    @Test func requiresText() async {
        await #expect(throws: ToolError.self) {
            _ = try await SpeakTool(synth: SpyseSynth(), mediaStore: tempStore()).execute(.object([:]))
        }
    }
    @Test func permissionIsRead() {
        #expect(SpeakTool(synth: SpyseSynth(), mediaStore: tempStore()).permission == .read)
    }
}
