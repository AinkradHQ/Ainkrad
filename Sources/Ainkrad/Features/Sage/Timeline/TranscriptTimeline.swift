import AinkradHostRuntime
import Foundation

/// Status of a single timeline step. `.running` == a tool call with no result yet.
enum StepStatus: Equatable { case running, done, error }

/// A tool step's payload: the call identity/input plus its resolved result.
struct ToolStepPayload: Equatable {
    let toolUseID: String
    let name: String
    let input: JSONValue
    let result: ToolResultSummary
}

/// One node on an agent turn's timeline. `duration`/`tokens` are the telemetry
/// seam — always nil in the presentation-layer phase, populated later by a
/// first-class Step model without changing this shape.
struct TurnStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case thinking(String)
        case text(String)
        case tool(ToolStepPayload)
        case todo([TodoItem])
        case plan(PlanArtifact)
    }
    let id: String
    let kind: Kind
    let status: StepStatus
    let duration: Duration?
    let tokens: Int?
}

/// A top-level transcript row: a distinct user prompt bubble, or one agent turn
/// rendered as a step timeline.
enum TranscriptItem: Identifiable, Equatable {
    case userBubble(index: Int, message: AgentMessage)
    case agentTurn(id: String, steps: [TurnStep])

    var id: String {
        switch self {
        case .userBubble(let index, _): return "user-\(index)"
        case .agentTurn(let id, _): return id
        }
    }
}

/// Memoizes `TranscriptTimelineBuilder.build` across renders.
///
/// The builder is pure, but "safe to call every render" is not the same as
/// "cheap to call every render". `SageRootView.body` re-evaluates on every
/// streamed chunk (`session.streamingText` changes), and each evaluation
/// rebuilt the entire timeline from the entire message history — allocating a
/// fresh `[TranscriptItem]` and every nested `[TurnStep]` per token, for a
/// transcript that had not changed at all.
///
/// The messages array is compared instead. That comparison is O(transcript),
/// but it is a scan over existing storage rather than a rebuild plus
/// allocations, and it turns the common streaming case (messages unchanged)
/// into a cache hit.
///
/// A reference type held in `@State` so it survives view-struct recreation.
@MainActor
final class TranscriptTimelineCache {
    private var lastMessages: [AgentMessage]?
    private var lastItems: [TranscriptItem] = []

    func items(for messages: [AgentMessage]) -> [TranscriptItem] {
        if let lastMessages, lastMessages == messages { return lastItems }
        let built = TranscriptTimelineBuilder.build(from: messages)
        lastMessages = messages
        lastItems = built
        return built
    }
}

/// Groups the flat `[AgentMessage]` transcript into per-turn timelines. Pure and
/// synchronous — but see `TranscriptTimelineCache` before calling it per render.
enum TranscriptTimelineBuilder {
    /// A user message is a PROMPT bubble when it carries any `.text` or `.image`
    /// block. A user message with only `.toolResult` blocks is the tool-result
    /// carrier for the current agent turn, not a prompt.
    private static func isPromptBubble(_ message: AgentMessage) -> Bool {
        guard message.role == .user else { return false }
        return message.content.contains {
            switch $0 {
            case .text, .image: return true
            default: return false
            }
        }
    }

    static func build(from messages: [AgentMessage]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var currentSteps: [TurnStep] = []
        var turnStartIndex: Int?

        func flushTurn() {
            guard let start = turnStartIndex, !currentSteps.isEmpty else {
                currentSteps = []
                turnStartIndex = nil
                return
            }
            items.append(.agentTurn(id: "turn-\(start)", steps: currentSteps))
            currentSteps = []
            turnStartIndex = nil
        }

        for (index, message) in messages.enumerated() {
            if isPromptBubble(message) {
                flushTurn()
                items.append(.userBubble(index: index, message: message))
                continue
            }
            // Sage message, or a tool-result-only user message: contribute steps.
            if turnStartIndex == nil { turnStartIndex = index }
            for (blockIndex, block) in message.content.enumerated() {
                switch block {
                case .thinking(let t):
                    currentSteps.append(
                        TurnStep(
                            id: "\(index)-\(blockIndex)", kind: .thinking(t),
                            status: .done, duration: nil, tokens: nil))
                case .text(let t):
                    currentSteps.append(
                        TurnStep(
                            id: "\(index)-\(blockIndex)", kind: .text(t),
                            status: .done, duration: nil, tokens: nil))
                case .toolUse(let id, let name, let input):
                    if name == "present_plan", let plan = PlanArtifact.from(input) {
                        // Keep only the LATEST present_plan in this turn so the node
                        // updates in place rather than stacking. Remove any prior plan
                        // step, then append. Stable id keeps SwiftUI diffing it as the
                        // same node across revisions.
                        currentSteps.removeAll { if case .plan = $0.kind { return true } else { return false } }
                        currentSteps.append(
                            TurnStep(
                                id: "plan-\(turnStartIndex ?? index)",
                                kind: .plan(plan), status: .done, duration: nil, tokens: nil))
                        break
                    }
                    if name == "todo_write" {
                        // Reconstruct the live checklist positionally: keep only the
                        // LATEST todo_write in this turn so the node updates in place
                        // rather than stacking. Remove any prior todo step, then append.
                        currentSteps.removeAll { if case .todo = $0.kind { return true } else { return false } }
                        currentSteps.append(
                            TurnStep(
                                id: "todo-\(turnStartIndex ?? index)",
                                kind: .todo(TodoItem.list(from: input)),
                                status: .done, duration: nil, tokens: nil))
                        break
                    }
                    let result = ToolResultLookup.summary(forToolUseID: id, after: index, in: messages)
                    let status: StepStatus = result.isPending ? .running : (result.isError ? .error : .done)
                    currentSteps.append(
                        TurnStep(
                            id: id,
                            kind: .tool(ToolStepPayload(toolUseID: id, name: name, input: input, result: result)),
                            status: status, duration: nil, tokens: nil))
                case .toolResult, .image:
                    break  // results are folded into their tool step; stray images ignored here
                }
            }
        }
        flushTurn()
        return items
    }
}
