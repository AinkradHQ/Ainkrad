import Foundation

/// Whether a just-settled turn is worth suggesting a skill for.
enum ReflectionVerdict: Equatable {
    case eligible(toolNames: [String])
    case notEligible
}

/// Pure, cheap heuristic run on every settled turn: was the LAST user turn a
/// non-trivial, clean, multi-tool procedure worth capturing as a reusable
/// skill? Deliberately conservative — a failed turn, any errored tool result,
/// or a chat/single-step turn is never eligible. No model call, no I/O.
enum SkillReflectionAdvisor {
    static func evaluate(
        _ messages: [AgentMessage], succeeded: Bool,
        minToolCalls: Int = 3
    ) -> ReflectionVerdict {
        guard succeeded else { return .notEligible }
        // Window = tail back to (and excluding) the last user message that
        // carries a `.text` block (the human prompt that opened this turn).
        var start = messages.count
        for idx in stride(from: messages.count - 1, through: 0, by: -1) {
            let m = messages[idx]
            let hasText = m.content.contains { if case .text = $0 { return true } else { return false } }
            if m.role == .user && hasText {
                start = idx
                break
            }
            start = idx
        }
        let window = messages[start...]
        var toolNames: [String] = []
        for m in window {
            for block in m.content {
                switch block {
                case .toolUse(_, let name, _):
                    if !toolNames.contains(name) { toolNames.append(name) }
                case .toolResult(_, _, let isError):
                    if isError { return .notEligible }
                default: break
                }
            }
        }
        return toolNames.count >= minToolCalls ? .eligible(toolNames: toolNames) : .notEligible
    }
}
