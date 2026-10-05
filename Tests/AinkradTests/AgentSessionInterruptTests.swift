import Foundation
import Testing

@testable import Ainkrad

/// Covers Task 8: `interrupt()` (hard-cancel the in-flight turn but keep the
/// transcript, so a subsequent `send` can redirect with prior context intact)
/// and the `unattended` auto-deny gate (a headless run's `.requireApproval`
/// resolves to a denied tool_result instead of parking on the approval
/// continuation, so it can never wedge waiting for a HUD that will never
/// come). `.timeLimit` proves the no-hang invariant: if the unattended gate
/// regressed back to parking, `await session.currentTask?.value` would hang
/// and the suite would fail on timeout rather than hanging the whole run.
@Suite("AgentSession interrupt/redirect", .timeLimit(.minutes(1)))
@MainActor
struct AgentSessionInterruptTests {
    @Test func interruptPreservesTranscript() async {
        let provider = SlowStubProvider()
        let session = TestSessionFactory.make(provider: provider)
        session.send("first question")
        await Task.yield()
        #expect(session.messages.contains { $0.role == .user && $0.text == "first question" })
        session.interrupt()
        #expect(session.state == .idle)
        // Transcript is intact (reset() would have cleared it).
        #expect(session.messages.contains { $0.text == "first question" })
        provider.release()
    }

    @Test func redirectContinuesWithContext() async {
        let provider = SlowStubProvider()
        let session = TestSessionFactory.make(provider: provider)
        session.send("do A")
        await Task.yield()
        session.interrupt()
        session.send("actually, do B")
        await Task.yield()
        // Both user turns are present — B was appended onto A's context.
        #expect(session.messages.filter { $0.role == .user }.count == 2)
        session.interrupt()
        provider.release()
    }

    @Test func interruptLeavesNoParkedApproval() async {
        // Interrupting while parked on an approval must unwedge the continuation
        // (not just cancel the task), so the loop's `withCheckedContinuation`
        // resolves and the abandoned turn unwinds instead of leaking forever.
        let provider = ScriptedApprovalProvider()
        let session = TestSessionFactory.make(provider: provider)
        session.send("edit")
        for _ in 0..<200 {
            if case .awaitingApproval = session.state { break }
            await Task.yield()
        }
        guard case .awaitingApproval = session.state else {
            Issue.record("expected awaitingApproval before interrupt")
            return
        }
        session.interrupt()
        #expect(session.state == .idle)
        // Transcript preserved: the user's turn is still there.
        #expect(session.messages.contains { $0.role == .user && $0.text == "edit" })
    }

    /// An unattended session denies (never wedges on) an approval-required call.
    /// The stub provider emits one edit_file (write → gated in .ask) then .done;
    /// with no HUD, the turn must settle to .idle with a denied tool_result.
    @Test func unattendedSessionDeniesApprovalRequiredCall() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ua-\(UUID().uuidString).txt").path
        try? "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let provider = EditOnceStubProvider(path: path, newContents: "v2")
        // .ask mode gates the write; unattended → auto-deny instead of awaiting approval.
        let session = TestSessionFactory.make(provider: provider, unattended: true)
        session.send("edit it")
        await session.currentTask?.value  // must NOT hang
        #expect(session.state == .idle)
        // The file was not changed (the write was denied before running).
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v1")
        #expect(
            session.messages.contains { m in
                m.content.contains {
                    if case .toolResult(_, _, let isError) = $0 { return isError } else { return false }
                }
            })
    }

    /// Never escalates: the always-on irreversible guard forces `.requireApproval`
    /// even in `.fullAuto` mode. Unattended must still deny it — it can only ever
    /// deny MORE than an attended run, never approve something the gate itself
    /// would have blocked.
    @Test func unattendedSessionDeniesIrreversibleCallEvenInFullAuto() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ua-\(UUID().uuidString).txt").path
        try? "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        // `.fullAuto` would normally auto-approve a plain write — but this tool
        // reports `isIrreversible == true`, so the always-on guard forces
        // `.requireApproval` regardless of mode, and unattended must still deny it.
        let provider = EditOnceStubProvider(path: path, newContents: "v2", toolName: "irreversible_tool")
        let session = TestSessionFactory.make(provider: provider, mode: .fullAuto, unattended: true)
        session.send("edit it")
        await session.currentTask?.value  // must NOT hang
        #expect(session.state == .idle)
        #expect(
            session.messages.contains { m in
                m.content.contains {
                    if case .toolResult(_, _, let isError) = $0 { return isError } else { return false }
                }
            })
    }

    /// Attended (default) path is unchanged: a requireApproval call still parks
    /// on `.awaitingApproval` and waits for a human decision.
    @Test func attendedSessionStillParksForApproval() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ua-\(UUID().uuidString).txt").path
        try? "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let provider = EditOnceStubProvider(path: path, newContents: "v2")
        let session = TestSessionFactory.make(provider: provider)  // unattended defaults false
        session.send("edit it")
        for _ in 0..<200 {
            if case .awaitingApproval = session.state { break }
            await Task.yield()
        }
        #expect(session.state != .idle)
        guard case .awaitingApproval = session.state else {
            Issue.record("expected awaitingApproval — attended path must still park")
            return
        }
        session.approve()
        await session.currentTask?.value
        #expect(session.state == .idle)
    }
}

/// A minimal provider that emits one write-classified tool call and then stalls
/// on `.done` for the SECOND turn only after being explicitly driven — used to
/// give `interruptLeavesNoParkedApproval` a stable window at `.awaitingApproval`
/// without racing a stub that auto-resolves immediately.
@MainActor
private final class ScriptedApprovalProvider: LLMProvider {
    private var turnIndex = 0

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        turnIndex += 1
        let isFirstTurn = turnIndex == 1
        return AsyncThrowingStream { cont in
            if isFirstTurn {
                cont.yield(.toolUseComplete(id: "1", name: "edit_file", input: .object([:])))
                cont.yield(.done(stopReason: "tool_use"))
            } else {
                cont.yield(.textDelta("done"))
                cont.yield(.done(stopReason: "end_turn"))
            }
            cont.finish()
        }
    }
}
