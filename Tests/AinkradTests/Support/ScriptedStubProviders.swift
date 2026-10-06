// Scripted `LLMProvider` doubles for the AgentSession tests, split out of
// TestSessionFactory.swift so neither file passes 500 lines.
import AinkradHostRuntime
import Foundation

@testable import Ainkrad

/// A `LLMProvider` double for the interrupt/redirect tests (Task 8): streams a
/// single `.thinkingDelta` and then suspends indefinitely until `release()` is
/// called, at which point it emits a trailing text turn and `.done`. Each call
/// to `send(...)` (i.e. each turn) re-arms its own release gate, so a session
/// that `interrupt()`s and then `send()`s again gets a fresh, independently
/// releasable stream.
@MainActor
final class SlowStubProvider: LLMProvider {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        released = false
        return AsyncThrowingStream { cont in
            Task { @MainActor in
                cont.yield(.thinkingDelta("thinking"))
                await self.waitForRelease()
                cont.yield(.textDelta("done"))
                cont.yield(.done(stopReason: "end_turn"))
                cont.finish()
            }
        }
    }

    private func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
        }
    }

    /// Unblocks whichever turn is currently parked, letting its stream finish.
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

/// A `LLMProvider` double for the unattended-gate test (Task 8): its first
/// turn emits one `edit_file` tool call (write-classified — gated in `.ask`
/// mode), its second (post tool-result) turn emits a trailing text + `.done`
/// so the loop settles to `.idle` regardless of whether the call was approved
/// or denied. `path`/`newContents` are carried in the tool-call input purely
/// for shape parity with a real edit tool; the registry's `FakeEditFileTool`
/// never actually touches the filesystem, so the test's file-unchanged
/// assertion is really proving the call never reached the tool at all.
@MainActor
final class EditOnceStubProvider: LLMProvider {
    private let path: String
    private let newContents: String
    private let toolName: String
    private var turnIndex = 0

    init(path: String, newContents: String, toolName: String = "edit_file") {
        self.path = path
        self.newContents = newContents
        self.toolName = toolName
    }

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        turnIndex += 1
        let isFirstTurn = turnIndex == 1
        let path = path
        let newContents = newContents
        let toolName = toolName
        return AsyncThrowingStream { cont in
            if isFirstTurn {
                cont.yield(
                    .toolUseComplete(
                        id: "1", name: toolName,
                        input: .object(["path": .string(path), "contents": .string(newContents)])))
                cont.yield(.done(stopReason: "tool_use"))
            } else {
                cont.yield(.textDelta("skipped"))
                cont.yield(.done(stopReason: "end_turn"))
            }
            cont.finish()
        }
    }
}

/// A `LLMProvider` double for the sandbox-compose wiring test (Task 21): its
/// first turn emits one `read_file` tool call (a `.read`-classified tool), its
/// second (post tool-result) turn emits a trailing text + `.done` so the loop
/// settles to `.idle` regardless of whether the call was allowed or blocked by
/// the sandbox layer. Mirrors `EditOnceStubProvider`'s shape for a read tool.
@MainActor
final class ReadOnceStubProvider: LLMProvider {
    private let path: String
    private var turnIndex = 0

    init(path: String) {
        self.path = path
    }

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        turnIndex += 1
        let isFirstTurn = turnIndex == 1
        let path = path
        return AsyncThrowingStream { cont in
            if isFirstTurn {
                cont.yield(.toolUseComplete(id: "1", name: "read_file", input: .object(["path": .string(path)])))
                cont.yield(.done(stopReason: "tool_use"))
            } else {
                cont.yield(.textDelta("done"))
                cont.yield(.done(stopReason: "end_turn"))
            }
            cont.finish()
        }
    }
}

/// Emits one `run_terminal` tool call on the first turn, plain text afterwards.
/// Used by the interrupt-force-kill test (`makeStreamingTerminal`).
@MainActor
final class SingleTerminalCallProvider: LLMProvider {
    private let command: String
    private var served = false
    init(command: String) { self.command = command }
    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let isFollowUp =
            messages.last?.content.contains {
                if case .toolResult = $0 { return true }
                return false
            } ?? false
        let command = command
        return AsyncThrowingStream { cont in
            if !isFollowUp {
                cont.yield(
                    .toolUseComplete(id: "1", name: "run_terminal", input: .object(["command": .string(command)])))
                cont.yield(.done(stopReason: "tool_use"))
            } else {
                cont.yield(.textDelta("ok"))
                cont.yield(.done(stopReason: "end_turn"))
            }
            cont.finish()
        }
    }
}
