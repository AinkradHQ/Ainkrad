// Tests/AinkradTests/TurnUndoTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("TurnUndo classification")
@MainActor
struct TurnUndoTests {
    @Test func flagsTerminalAndGitAsIrreversible() {
        let turn = [
            AgentMessage(
                role: .assistant,
                content: [
                    .toolUse(id: "1", name: "edit_file", input: .object(["path": .string("/x")])),
                    .toolUse(id: "2", name: "run_terminal", input: .object(["command": .string("rm x")])),
                    .toolUse(id: "3", name: "mcp/gitmage/commit", input: .object(["repoPath": .string("/r")])),
                ])
        ]
        let notes = TurnUndo.classifyIrreversible(turn)
        // run_terminal + the MCP git call, not edit_file. Git arrives as
        // `mcp/gitmage/*` now that the bespoke `git_op` tool is gone, so the
        // namespace prefix — not a flat name — is what has to catch it.
        #expect(notes.count == 2)
        #expect(notes.contains { $0.contains("run_terminal") })
        #expect(notes.contains { $0.contains("mcp/gitmage/commit") })
    }

    @Test func pureReadTurnHasNoIrreversibles() {
        let turn = [
            AgentMessage(
                role: .assistant,
                content: [
                    .toolUse(id: "1", name: "read_file", input: .object(["path": .string("/x")]))
                ])
        ]
        #expect(TurnUndo.classifyIrreversible(turn).isEmpty)
    }

    @Test func emptyTurnHasNoIrreversibles() {
        #expect(TurnUndo.classifyIrreversible([]).isEmpty)
    }

    @Test func multipleCallsToSameIrreversibleToolEachYieldANote() {
        let turn = [
            AgentMessage(
                role: .assistant,
                content: [
                    .toolUse(id: "1", name: "run_terminal", input: .object(["command": .string("ls")])),
                    .toolUse(id: "2", name: "run_terminal", input: .object(["command": .string("pwd")])),
                ])
        ]
        #expect(TurnUndo.classifyIrreversible(turn).count == 2)
    }
}
