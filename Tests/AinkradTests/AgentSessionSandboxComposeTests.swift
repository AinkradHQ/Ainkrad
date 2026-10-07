// Tests/AinkradTests/AgentSessionSandboxComposeTests.swift
import Foundation
import Testing

@testable import Ainkrad

/// M7 Slice 3b Task 21 — proves `AgentSession.execute`'s wiring of
/// `SandboxPermissionPolicy.compose`: a non-nil `sandboxAllowList` that excludes
/// a called tool must deny it (surfaced as an error `tool_result` mentioning
/// "sandbox") WITHOUT ever running the tool, and a `nil` `sandboxAllowList` (every
/// pre-Task-21 call site) must remain byte-identical to today's behavior.
/// `SandboxPermissionPolicy.compose` itself is unit-tested inside Slice 6; this
/// suite validates only the AgentSession WIRING (decision mapping).
@Suite("AgentSession sandbox compose")
@MainActor
struct AgentSessionSandboxComposeTests {
    @Test func sandboxAllowListDeniesExcludedTool() async {
        let provider = ReadOnceStubProvider(path: "/etc/hosts")
        let session = TestSessionFactory.make(
            provider: provider,
            unattended: true,
            sandboxAllowList: ["run_terminal"])  // read_file NOT in the sandbox surface
        session.send("read the file")
        await session.currentTask?.value
        #expect(session.state == .idle)
        #expect(
            session.messages.contains { m in
                m.content.contains {
                    if case .toolResult(_, let content, let isError) = $0 {
                        return isError && content.contains("sandbox")
                    }
                    return false
                }
            })
    }

    @Test func nilSandboxAllowListIsUnrestricted() async {
        let provider = ReadOnceStubProvider(path: "/etc/hosts")
        let session = TestSessionFactory.make(provider: provider, unattended: true, sandboxAllowList: nil)
        session.send("read the file")
        await session.currentTask?.value
        #expect(session.state == .idle)  // no sandbox layer applied
        // With no sandbox layer, `execute` never reaches `SandboxPermissionPolicy.compose`
        // at all — whatever the outcome (here: the unattended gate auto-denies the
        // gated read, per Task 8, exactly as it would pre-Task-21), the denial reason
        // must never mention "sandbox".
        #expect(
            !session.messages.contains { m in
                m.content.contains {
                    if case .toolResult(_, let content, let isError) = $0 {
                        return isError && content.contains("sandbox")
                    }
                    return false
                }
            })
    }
}
