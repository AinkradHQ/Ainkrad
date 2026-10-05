// Tests/AinkradTests/AgentSessionUndoTests.swift
//
// Task 10: turn-level /undo + /retry. Uses two local `LLMProvider` doubles (this
// file only) that, unlike the shared `EditOnceStubProvider`/`FakeEditFileTool`
// harness, drive the REAL `EditFileTool(journal:)` registered by
// `TestSessionFactory.make(provider:editJournal:)` — the undo assertions need
// the on-disk file to actually change and revert, not just prove a tool call
// was (or wasn't) dispatched.
import Foundation
import Testing

@testable import Ainkrad

/// A single turn that emits BOTH a real `edit_file` call and an irreversible
/// `run_terminal` call (batched in the same assistant turn, as a real provider
/// would when the model decides to edit a file and then run a command in one
/// go), then finishes with plain text on the follow-up call.
@MainActor
final class EditAndTerminalStubProvider: LLMProvider {
    private let path: String
    private let oldString: String
    private let newString: String
    private var servedFirstTurn = false

    init(path: String, oldString: String, newString: String) {
        self.path = path
        self.oldString = oldString
        self.newString = newString
    }

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let isFollowUp =
            messages.last?.content.contains {
                if case .toolResult = $0 { return true }
                return false
            } ?? false
        let path = path
        let oldString = oldString
        let newString = newString
        return AsyncThrowingStream { cont in
            if !isFollowUp {
                cont.yield(
                    .toolUseComplete(
                        id: "1", name: "edit_file",
                        input: .object([
                            "path": .string(path), "old_string": .string(oldString),
                            "new_string": .string(newString),
                        ])))
                cont.yield(
                    .toolUseComplete(
                        id: "2", name: "run_terminal",
                        input: .object(["command": .string("echo hi")])))
                cont.yield(.done(stopReason: "tool_use"))
            } else {
                cont.yield(.textDelta("ok"))
                cont.yield(.done(stopReason: "end_turn"))
            }
            cont.finish()
        }
    }
}

@Suite("AgentSession undo/retry", .timeLimit(.minutes(1)))
@MainActor
struct AgentSessionUndoTests {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("u-\(UUID().uuidString).txt").path
    }

    @Test func undoRestoresFileAndTranscript() async {
        let path = tempPath()
        try? "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let journal = EditJournal()
        let provider = MultiEditStubProvider(path: path, edits: [("v1", "v2")])
        let session = TestSessionFactory.make(provider: provider, mode: .fullAuto, editJournal: journal)

        session.send("update the file")
        await session.currentTask?.value
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v2")

        let summary = session.undoLastTurn()
        #expect(summary.revertedEdits == 1)
        #expect(summary.irreversible.isEmpty)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v1")
        #expect(session.messages.isEmpty)  // transcript rewound to before the turn
    }

    @Test func undoOfIrreversibleTurnRefusesAndRevertsNothing() async {
        let path = tempPath()
        try? "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let journal = EditJournal()
        let provider = EditAndTerminalStubProvider(path: path, oldString: "v1", newString: "v2")
        let session = TestSessionFactory.make(provider: provider, mode: .fullAuto, editJournal: journal)

        session.send("edit then run a command")
        await session.currentTask?.value
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v2")
        let transcriptCountBefore = session.messages.count

        let summary = session.undoLastTurn()
        #expect(summary.revertedEdits == 0)
        #expect(!summary.irreversible.isEmpty)
        #expect(summary.irreversible.contains { $0.contains("run_terminal") })
        // All-or-nothing: the file edit is NOT reverted either, and the
        // transcript is left completely untouched.
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v2")
        #expect(session.messages.count == transcriptCountBefore)

        // A repeated /undo on the same refused turn is stable (idempotent
        // refusal), not a crash or a partial revert on a second attempt.
        let secondSummary = session.undoLastTurn()
        #expect(secondSummary.revertedEdits == 0)
        #expect(!secondSummary.irreversible.isEmpty)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v2")
    }

    @Test func multipleUndosWalkBackTurnByTurn() async {
        let path = tempPath()
        try? "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let journal = EditJournal()
        let provider = MultiEditStubProvider(path: path, edits: [("v1", "v2"), ("v2", "v3")])
        let session = TestSessionFactory.make(provider: provider, mode: .fullAuto, editJournal: journal)

        session.send("first edit")
        await session.currentTask?.value
        session.send("second edit")
        await session.currentTask?.value
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v3")

        let first = session.undoLastTurn()
        #expect(first.revertedEdits == 1)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v2")
        #expect(!session.messages.isEmpty)  // first turn's history remains

        let second = session.undoLastTurn()
        #expect(second.revertedEdits == 1)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v1")
        #expect(session.messages.isEmpty)

        let third = session.undoLastTurn()
        #expect(third.revertedEdits == 0)
        #expect(third.irreversible.isEmpty)
    }

    @Test func nothingToUndoIsANoop() {
        let session = TestSessionFactory.make(provider: RecordingProvider(script: []))
        let summary = session.undoLastTurn()
        #expect(summary == TurnUndoSummary(revertedEdits: 0, irreversible: []))
    }

    @Test func retryResendsLastPromptAfterUndoingIt() async {
        let provider = RecordingProvider(script: [.textDelta("reply"), .done(stopReason: "end_turn")])
        let session = TestSessionFactory.make(provider: provider, mode: .fullAuto)

        session.send("hello")
        await session.currentTask?.value
        #expect(session.messages.count == 2)  // user + assistant reply
        #expect(provider.callCount == 1)

        session.retryLastTurn()
        await session.currentTask?.value

        #expect(provider.callCount == 2)  // undone + resent, one fresh provider call
        #expect(session.messages.count == 2)  // rewound then re-settled to the same shape
        #expect(session.messages.first?.text == "hello")
    }

    @Test func retryWithNoTurnsIsANoop() {
        let session = TestSessionFactory.make(provider: RecordingProvider(script: []))
        session.retryLastTurn()
        #expect(session.messages.isEmpty)
    }
}
