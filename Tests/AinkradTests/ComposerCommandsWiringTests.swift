// Tests/AinkradTests/ComposerCommandsWiringTests.swift
//
// M7 Slice 5c Task 22a: `/compact` and `/export` wiring. The plan's draft test
// referenced `SageCommands.makeBuiltins`, which never existed — the real
// factory is `BuiltinCommands.make` (Commands/CommandRegistry.swift). These
// tests exercise it against a live `AgentSession` so a vacuous "command is
// registered" check isn't the only coverage.
import Foundation
import AppKit
import Testing
@testable import Ainkrad
import AinkradHostRuntime

/// A scripted `LLMProvider` double, mirroring `AgentSessionToolLoopTests`'
/// file-private `ScriptedProvider` — kept local here so this file doesn't take
/// on a cross-file test-support dependency for one test.
@MainActor
private final class ScriptedToolCallProvider: LLMProvider {
    var turns: [[AgentEvent]]
    init(_ turns: [[AgentEvent]]) { self.turns = turns }
    func send(messages: [AgentMessage], system: String, tools: [AgentToolSchema],
              model: AgentModelConfig, credential: ProviderCredential) -> AsyncThrowingStream<AgentEvent, Error> {
        let batch = turns.isEmpty ? [] : turns.removeFirst()
        return AsyncThrowingStream { cont in
            for e in batch { cont.yield(e) }
            cont.finish()
        }
    }
}

@MainActor
private struct WriteTool: AgentTool {
    let name = "write_tool"
    let description = "writes something"
    var parametersSchema: JSONValue { .object(["type": .string("object")]) }
    let permission: ToolPermissionClass = .write
    func execute(_ input: JSONValue) async throws -> ToolResult { ToolResult(content: "done", isError: false) }
}

/// Spins the main actor until `session` parks on `.awaitingApproval`, bounded so
/// a regression fails fast instead of hanging the suite forever. Mirrors
/// `AgentSessionToolLoopTests.waitForApproval`.
@MainActor
private func waitForAwaitingApproval(_ session: AgentSession, maxYields: Int = 200) async -> Bool {
    for _ in 0..<maxYields {
        if case .awaitingApproval = session.state { return true }
        await Task.yield()
    }
    return false
}

@Suite("Composer commands wiring")
@MainActor
struct ComposerCommandsWiringTests {
    @Test func builtinCommandsRegistered() {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(
            runtime: RuntimeOptionsStore(persistence: InMemoryPersistenceStore()),
            usage: UsageTracker(persistence: InMemoryPersistenceStore(), prices: ModelPriceTable()),
            router: nil, catalog: nil))
        let names = Set(reg.all().map(\.name))
        #expect(names.isSuperset(of: ["new", "model", "think", "verbose", "trace", "usage", "compact", "export"]))
    }

    @Test func compactShrinksALongTranscriptAndReportsWhatHappened() async {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(commands: reg)

        // NoopProvider never emits `.done`, so each `send` settles to `.failed`
        // without appending an assistant reply — irrelevant here, since we only
        // need the USER messages accumulating past the compactor's `keepRecent`
        // threshold (6).
        for i in 1...8 {
            session.send("message \(i)")
            await session.currentTask?.value
        }
        #expect(session.messages.count == 8)

        session.send("/compact")

        // `replaceMessages` leaves 7 (1 synthetic summary + 6 kept tail); `send`
        // then appends the command's own note as one more assistant message.
        #expect(session.messages.count == 8)
        #expect(session.messages.first?.text.contains("summarized") == true)
        guard case .assistant = session.messages.last?.role else { Issue.record("expected an assistant note"); return }
        #expect(session.messages.last?.text.contains("Compacted 2") == true)
    }

    @Test func compactDeclinesWhenTranscriptIsAlreadyShort() {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(commands: reg)
        session.send("/compact")
        #expect(session.messages.count == 1) // only the "nothing to compact" note
        #expect(session.messages.last?.text.contains("Nothing to compact") == true)
    }

    /// Deliberately does NOT touch `NSPasteboard.general`. This test used to
    /// assert against the real clipboard, which meant every `xcodebuild test`
    /// — including one an agent ran in the background — threw away whatever the
    /// developer had copied. A test must not clobber a resource that belongs to
    /// the person running it, so `/export` writes through a `TextPasteboard`
    /// seam and this drives a recording double.
    @Test func exportRendersMarkdownAndCopiesItToThePasteboard() {
        let pasteboard = RecordingPasteboard()
        let reg = CommandRegistry(builtins: BuiltinCommands.make(
            runtime: nil, usage: nil, router: nil, catalog: nil, pasteboard: pasteboard))
        let session = TestSessionFactory.make(commands: reg)
        let result = reg.run("/export", on: TestSessionFactory.make(commands: reg))
        // Fresh empty session: nothing to export yet, not a stub message.
        #expect(result == .handled(note: "Nothing to export yet."))
        #expect(pasteboard.copied == nil, "an empty session must not write to the clipboard at all")

        session.send("hello there")
        let exportResult = reg.run("/export", on: session)
        guard case .handled(let note) = exportResult, let note else { Issue.record("expected a handled note"); return }
        #expect(note.contains("Copied the transcript"))
        #expect(!note.lowercased().contains("isn't implemented"))

        let clipboard = pasteboard.copied
        #expect(clipboard?.contains("# Conversation") == true)
        #expect(clipboard?.contains("hello there") == true)
    }

    /// Task 22a gate follow-up (Fix 1): `/compact` must be a safe no-op while a
    /// turn is in flight, since it rewrites the transcript via `replaceMessages`
    /// — firing it mid-turn would clobber whatever the in-flight turn has
    /// already appended with a stale pre-turn snapshot. Parks the session on
    /// `.awaitingApproval` (a write-permission tool call under `.ask` mode) as a
    /// deterministic, non-idle "turn in progress" state, then fires `/compact`
    /// while parked there.
    @Test func compactIsANoOpWhileATurnIsInProgress() async {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let provider = ScriptedToolCallProvider([
            [.toolUseComplete(id: "1", name: "write_tool", input: .object([:])), .done(stopReason: "tool_use")],
        ])
        let persistence = InMemoryPersistenceStore()
        let ws = UUID()
        let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        permissions.setMode(.ask)
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        _ = connections.addConnection(preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
                                      baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let config = AgentConfigStore(persistence: persistence)
        let context = AgentContextService(hub: AgentContextRegistryHub(),
                                          settings: AgentContextSettingsStore(persistence: persistence))
        let session = AgentSession(
            providerFor: { _ in provider },
            connections: connections, config: config, context: context,
            registry: AgentToolRegistry(tools: [WriteTool()]), permissions: permissions,
            commands: reg)

        // Seed the transcript past `/compact`'s `keepRecent` (6) threshold BEFORE
        // the turn starts, so an absent/broken guard would visibly mutate
        // `messages` here rather than silently no-op via the "too short" path.
        session.replaceMessages((1...6).map { AgentMessage(role: .user, text: "seed \($0)") })

        session.send("edit something")
        guard await waitForAwaitingApproval(session) else { Issue.record("expected awaitingApproval"); return }
        #expect(session.state != .idle)
        #expect(session.messages.count > 6)

        let before = session.messages
        session.send("/compact")

        // The guard's busy note is appended (as any command note is, by
        // `send()`), but everything BEFORE it — the seeded transcript plus the
        // in-flight tool-use turn — must be byte-for-byte unchanged: no
        // `replaceMessages` rewrite happened.
        #expect(Array(session.messages.dropLast()) == before)
        #expect(session.messages.count == before.count + 1)
        #expect(session.messages.last?.text.contains("Can't compact while a turn is in progress") == true)
        // Still parked — the guard didn't perturb the in-flight approval either.
        guard case .awaitingApproval = session.state else { Issue.record("expected still awaitingApproval"); return }

        // Unwedge cleanly so the test doesn't leak a parked continuation.
        session.deny(reason: "test cleanup")
        await session.currentTask?.value
    }
}


/// Captures what `/export` would have put on the clipboard.
final class RecordingPasteboard: TextPasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    var copied: String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func copy(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        value = text
    }
}
