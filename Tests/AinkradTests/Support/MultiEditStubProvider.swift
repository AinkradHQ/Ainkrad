// Tests/AinkradTests/Support/MultiEditStubProvider.swift
//
// Hoisted from AgentSessionUndoTests.swift (Task 10) so AgentSessionCheckpointTests
// (Task 5 of Checkpoint & Rewind) can share it too. Verbatim relocation — no
// behavior change.
import Foundation

@testable import Ainkrad

/// Emits one `edit_file(old_string, new_string)` tool call per queued edit, one
/// user turn at a time: a turn that begins with a fresh user message serves the
/// next queued edit; a turn that begins with a tool-result (the follow-up call
/// inside the SAME turn's loop) finishes with plain text. Turns run out of
/// queued edits reply with plain text immediately, so extra `send`s are inert.
@MainActor
final class MultiEditStubProvider: LLMProvider {
    private let path: String
    private var edits: [(old: String, new: String)]
    private(set) var callCount = 0

    init(path: String, edits: [(old: String, new: String)]) {
        self.path = path
        self.edits = edits
    }

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        callCount += 1
        let isFollowUp =
            messages.last?.content.contains {
                if case .toolResult = $0 { return true }
                return false
            } ?? false
        let path = path
        let nextEdit: (old: String, new: String)? = (!isFollowUp && !edits.isEmpty) ? edits.removeFirst() : nil
        return AsyncThrowingStream { cont in
            if let nextEdit {
                cont.yield(
                    .toolUseComplete(
                        id: UUID().uuidString, name: "edit_file",
                        input: .object([
                            "path": .string(path), "old_string": .string(nextEdit.old),
                            "new_string": .string(nextEdit.new),
                        ])))
                cont.yield(.done(stopReason: "tool_use"))
            } else {
                cont.yield(.textDelta("ok"))
                cont.yield(.done(stopReason: "end_turn"))
            }
            cont.finish()
        }
    }
}
