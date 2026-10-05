import AinkradHostRuntime
import Foundation

struct AgentModelConfig: Equatable, Sendable {
    var model: String  // e.g. "claude-opus-4-8" / "gpt-5" / "gemini-2.5-pro"
    var effort: String  // Claude only; ignored by other kinds
}

enum AgentEvent: Equatable, Sendable {
    case thinkingDelta(String)
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolInputDelta(id: String, partialJSON: String)
    case toolUseComplete(id: String, name: String, input: JSONValue)
    case done(stopReason: String?)
    case usage(TokenUsage)
    case failed(String)
}
