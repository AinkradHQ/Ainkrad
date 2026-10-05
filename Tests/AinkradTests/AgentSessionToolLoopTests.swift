import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
private final class ScriptedProvider: LLMProvider {
    // Each call returns the next scripted batch of events.
    var turns: [[AgentEvent]]
    private(set) var sendCount = 0
    init(_ turns: [[AgentEvent]]) { self.turns = turns }
    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        sendCount += 1
        let batch = turns.isEmpty ? [] : turns.removeFirst()
        return AsyncThrowingStream { cont in
            for e in batch { cont.yield(e) }
            cont.finish()
        }
    }
}

@MainActor
private struct OKTool: AgentTool {
    let name = "ok_tool"
    let description = "returns ok"
    var parametersSchema: JSONValue { .object(["type": .string("object")]) }
    let permission: ToolPermissionClass
    func execute(_ input: JSONValue) async throws -> ToolResult { ToolResult(content: "OK", isError: false) }
}

@MainActor
private func makeSession(
    provider: LLMProvider, tool: OKTool,
    mode: AgentPermissionMode, gateReads: Bool = true
) -> AgentSession {
    let persistence = InMemoryPersistenceStore()
    let ws = UUID()
    let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
    permissions.setMode(mode)
    permissions.setGateReads(gateReads)
    let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
    // Seed a key so resolveAPIKey succeeds (config defaults to the Claude provider).
    _ = connections.addConnection(
        preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
        baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
    let config = AgentConfigStore(persistence: persistence)
    let context = AgentContextService(
        hub: AgentContextRegistryHub(),
        settings: AgentContextSettingsStore(persistence: persistence))
    return AgentSession(
        providerFor: { _ in provider },
        connections: connections, config: config, context: context,
        registry: AgentToolRegistry(tools: [tool]), permissions: permissions)
}

/// Spins the main actor until `session` parks on `.awaitingApproval`, bounded so
/// a regression fails fast instead of hanging the suite forever.
@MainActor
private func waitForApproval(_ session: AgentSession, maxYields: Int = 200) async -> Bool {
    for _ in 0..<maxYields {
        if case .awaitingApproval = session.state { return true }
        await Task.yield()
    }
    return false
}

@Suite("AgentSession tool loop")
@MainActor
struct AgentSessionToolLoopTests {
    @Test func readToolRunsWithoutApprovalThenCompletes() async {
        let provider = ScriptedProvider([
            [.toolUseComplete(id: "1", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            [.textDelta("done"), .done(stopReason: "end_turn")],
        ])
        let session = makeSession(provider: provider, tool: OKTool(permission: .read), mode: .ask, gateReads: false)
        session.send("go")
        await session.currentTask?.value
        #expect(session.state == .idle)
        #expect(session.messages.last?.text == "done")
    }

    @Test func writeToolWaitsForApprovalInAskMode() async {
        let provider = ScriptedProvider([
            [.toolUseComplete(id: "1", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            [.textDelta("applied"), .done(stopReason: "end_turn")],
        ])
        let session = makeSession(provider: provider, tool: OKTool(permission: .write), mode: .ask)
        session.send("edit")
        guard await waitForApproval(session) else {
            Issue.record("expected awaitingApproval")
            return
        }
        session.approve()
        await session.currentTask?.value
        #expect(session.state == .idle)
        #expect(session.messages.last?.text == "applied")
    }

    @Test func denyFeedsReasonBack() async {
        let provider = ScriptedProvider([
            [.toolUseComplete(id: "1", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            [.textDelta("ok, skipped"), .done(stopReason: "end_turn")],
        ])
        let session = makeSession(provider: provider, tool: OKTool(permission: .write), mode: .ask)
        session.send("edit")
        guard await waitForApproval(session) else {
            Issue.record("expected awaitingApproval")
            return
        }
        session.deny(reason: "no thanks")
        await session.currentTask?.value
        // The tool_result fed back carries the denial reason.
        let toolResult = session.messages.flatMap(\.content).compactMap { block -> String? in
            if case .toolResult(_, let content, let isError) = block, isError { return content }
            return nil
        }.first
        #expect(toolResult == "no thanks")
        #expect(session.state == .idle)
    }

    @Test func resetDuringApprovalDoesNotSpawnTurn() async {
        let provider = ScriptedProvider([
            [.toolUseComplete(id: "1", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            // A second batch exists only to prove a zombie turn WOULD consume it
            // if the loop failed to bail on cancellation.
            [.textDelta("zombie"), .done(stopReason: "end_turn")],
        ])
        let session = makeSession(provider: provider, tool: OKTool(permission: .write), mode: .ask)
        session.send("edit")
        guard await waitForApproval(session) else {
            Issue.record("expected awaitingApproval")
            return
        }
        #expect(provider.sendCount == 1)

        // Capture the in-flight task before reset() nils the property, so we can
        // await the cancelled task fully unwinding before asserting.
        let inFlight = session.currentTask
        session.reset()
        await inFlight?.value

        #expect(session.messages.isEmpty)
        #expect(session.state == .idle)
        // No re-send after reset: the cancellation guard bailed before the loop
        // could resurrect the transcript and call provider.send again.
        #expect(provider.sendCount == 1)
    }

    @Test func approveAlwaysAllowlistsToolAndSkipsFutureApproval() async {
        let persistence = InMemoryPersistenceStore()
        let ws = UUID()
        let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        permissions.setMode(.autoApprove)
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        _ = connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let config = AgentConfigStore(persistence: persistence)
        let context = AgentContextService(
            hub: AgentContextRegistryHub(),
            settings: AgentContextSettingsStore(persistence: persistence))
        let tool = OKTool(permission: .write)
        let provider = ScriptedProvider([
            [.toolUseComplete(id: "1", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            [.textDelta("first"), .done(stopReason: "end_turn")],
            [.toolUseComplete(id: "2", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            [.textDelta("second"), .done(stopReason: "end_turn")],
        ])
        let session = AgentSession(
            providerFor: { _ in provider },
            connections: connections, config: config, context: context,
            registry: AgentToolRegistry(tools: [tool]), permissions: permissions)

        session.send("edit")
        guard await waitForApproval(session) else {
            Issue.record("expected awaitingApproval")
            return
        }
        session.approve(always: true)
        await session.currentTask?.value
        #expect(session.state == .idle)
        #expect(session.messages.last?.text == "first")
        #expect(permissions.allowlist.contains("ok_tool"))

        // A subsequent identical call auto-approves: no second .awaitingApproval.
        session.send("edit again")
        await session.currentTask?.value
        #expect(session.state == .idle)
        #expect(session.messages.last?.text == "second")
    }

    @Test func onSettledFiresExactlyOnceAfterCompletedTurn() async {
        let provider = ScriptedProvider([
            [.textDelta("done"), .done(stopReason: "end_turn")]
        ])
        let session = makeSession(provider: provider, tool: OKTool(permission: .read), mode: .ask, gateReads: false)
        var settledCount = 0
        var stateAtFire: AgentSession.State?
        session.onSettled = {
            settledCount += 1
            stateAtFire = session.state
        }
        session.send("go")
        // Not fired while the turn is still in flight (streaming/thinking).
        #expect(settledCount == 0)
        await session.currentTask?.value
        #expect(settledCount == 1)
        #expect(stateAtFire == .idle)
        #expect(session.state == .idle)
    }

    @Test func onSettledDoesNotFireAtApprovalPauseOnlyAfterCompletion() async {
        let provider = ScriptedProvider([
            [.toolUseComplete(id: "1", name: "ok_tool", input: .object([:])), .done(stopReason: "tool_use")],
            [.textDelta("applied"), .done(stopReason: "end_turn")],
        ])
        let session = makeSession(provider: provider, tool: OKTool(permission: .write), mode: .ask)
        var settledCount = 0
        session.onSettled = { settledCount += 1 }
        session.send("edit")
        guard await waitForApproval(session) else {
            Issue.record("expected awaitingApproval")
            return
        }
        // Parked on the approval gate: settled() must not have fired yet.
        #expect(settledCount == 0)
        session.approve()
        await session.currentTask?.value
        #expect(settledCount == 1)
        #expect(session.state == .idle)
        #expect(session.messages.last?.text == "applied")
    }
}
