import Foundation
import Testing
@testable import Ainkrad

/// Derives a block's "type" for assertions across providers. Claude and
/// OpenAI-compatible blocks carry an explicit `"type"` key; Gemini's `parts`
/// blocks (`text`, `functionCall`, `functionResponse`, `inlineData`) don't, so
/// the block's own single key stands in for its type there.
private extension Array where Element == [String: Any] {
    var blockTypesForTesting: [String] {
        map { block in
            if let type = block["type"] as? String { return type }
            return block.keys.first ?? ""
        }
    }
}

@Suite("Provider .thinking handling")
struct ProviderThinkingBlockTests {
    private let message = AgentMessage(
        role: .assistant,
        content: [.thinking("internal reasoning"), .text("visible answer")]
    )

    /// WHAT THIS ACTUALLY COVERS, stated precisely because the obvious reading
    /// is wrong: `wireMessage` iterates `message.wireContent`, which ALREADY
    /// strips `.thinking` before the switch runs. So these tests exercise that
    /// stripping — they do NOT reach the switch's `.thinking` case, and they
    /// would pass against the old `preconditionFailure` code too.
    ///
    /// The switch case cannot be tested from here. It is guarded by
    /// `assertionFailure`, which TRAPS in Debug — and the suite runs Debug — so
    /// any test that genuinely reached it would kill the runner. That is the
    /// intended design: assert loudly in development, drop-and-log in Release.
    /// The Release behaviour is deliberately unreachable from a Debug test.
    ///
    /// These are still worth keeping: they pin the `wireContent` contract that
    /// makes the switch case unreachable in the first place. If that contract
    /// ever breaks, these fail before a user's session dies.
    @Test func claudeWireContentStripsThinkingBeforeSerialization() {
        let wire = ClaudeProvider.wirePayloadForTesting(message)
        let types = wire.blockTypesForTesting
        #expect(!types.contains("thinking"))
        #expect(types.contains("text"))
    }

    @Test func geminiWireContentStripsThinkingBeforeSerialization() {
        let wire = GeminiProvider.wirePayloadForTesting(message)
        #expect(!wire.blockTypesForTesting.contains("thinking"))
    }

    @Test func openAICompatibleWireContentStripsThinkingBeforeSerialization() {
        let wire = OpenAICompatibleProvider.wirePayloadForTesting(message)
        #expect(!wire.blockTypesForTesting.contains("thinking"))
    }

    @Test func aMessageWithNoThinkingIsUnchanged() {
        let plain = AgentMessage(role: .assistant, content: [.text("just text")])
        #expect(ClaudeProvider.wirePayloadForTesting(plain).blockTypesForTesting == ["text"])
    }
}
