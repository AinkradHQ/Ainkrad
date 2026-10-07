import AinkradHostRuntime
import Foundation
import Observation

/// The tool-use agent loop: owns the transcript, in-flight streaming buffers,
/// the tool registry, and the per-turn approval gate. Runs
/// send → tool_use → execute (gated) → tool_result → repeat until end_turn.
@MainActor
@Observable
final class AgentSession {
    struct PendingApproval: Equatable, Sendable {
        let call: ToolCall
        let preview: ToolApprovalPreview
    }

    enum State: Equatable {
        case idle
        case thinking
        case streaming
        case callingTool(String)
        case awaitingApproval(PendingApproval)
        case failed(String)
    }

    static let defaultPrompt = """
        You are Ainkrad's built-in assistant, embedded in a native macOS \
        developer workspace. You can read and edit files using the provided tools. \
        Answer concisely and precisely. For structured or comparative output — \
        tables, diagrams, charts, code, status boards, or several related cards — \
        prefer the `scry_render` tool over inline chat; it persists as movable \
        HUD cards you can update in place for live progress. Keep short \
        conversational answers and one-off inline snippets in chat. Don't invoke \
        tools or skills for greetings, small talk, or when no concrete task is \
        requested — just reply.
        """

    var messages: [AgentMessage] = []
    var state: State = .idle
    var streamingText: String = ""
    var streamingThinking: String = ""
    /// Pre-parsed blocks for `streamingText`, published on the same coalesced
    /// tick. The view renders these instead of re-parsing the whole message —
    /// see `MarkdownStreamParser`.
    var streamingBlocks: [MarkdownBlock] = []

    /// Hunk ids the user has toggled to REJECT on the pending edit_file approval.
    /// Reset whenever a new approval is parked; read by `approve()` to rebuild a
    /// partial edit. Empty = accept the whole edit (unchanged behavior).
    var rejectedHunkIDs: Set<Int> = []
    func setRejectedHunkIDs(_ ids: Set<Int>) { rejectedHunkIDs = ids }

    /// Token usage accumulated from the most recently completed turn's `.usage`
    /// events. Consumed by `UsageTracker` (Task 9) to compute per-turn cost.
    var lastTurnUsage: TokenUsage = .zero

    /// The model ID actually attributed to the most recent `usage?.record(...)` call —
    /// the model failover/escalation ACTUALLY settled on, not necessarily the one
    /// `resolveTurn` originally picked. `nil` before any turn has settled.
    var lastUsageAttributedModel: String?

    /// A skill-capture hint surfaced after a complex, clean turn (Task 2).
    /// Passive — the UI offers it; it never proposes on its own. Cleared at the
    /// start of the next turn and on reset.
    private(set) var pendingSkillSuggestion: SkillSuggestion?

    /// Recomputes `pendingSkillSuggestion` from a settled turn. Internal so the
    /// settle path and tests can drive it without a full turn.
    func updateSkillSuggestion(from messages: [AgentMessage], succeeded: Bool) {
        switch SkillReflectionAdvisor.evaluate(messages, succeeded: succeeded) {
        case .eligible(let toolNames): pendingSkillSuggestion = SkillSuggestion(toolNames: toolNames)
        case .notEligible: pendingSkillSuggestion = nil
        }
    }

    /// Accepts the pending skill suggestion: sends the reflection directive as a
    /// normal turn (so `propose_skill` runs through the usual gate) and clears the
    /// hint. No-op when nothing is pending.
    func acceptSkillSuggestion() {
        guard let suggestion = pendingSkillSuggestion else { return }
        pendingSkillSuggestion = nil
        send(SkillReflectionDirective.build(toolNames: suggestion.toolNames))
    }

    /// Dismisses the pending suggestion without sending anything.
    func dismissSkillSuggestion() { pendingSkillSuggestion = nil }

    /// Fired whenever a turn settles (the tool loop returns to `.idle` inside
    /// `runConversation`) — every-settle is the host's only reliable trigger,
    /// since there is no session-end signal. NOT fired by `reset()`'s `.idle`.
    var onSettled: (() -> Void)?

    /// The in-flight turn's task, exposed so tests can await settlement.
    /// Not part of the UI-facing contract.
    private(set) var currentTask: Task<Void, Never>?

    /// Resolves the ordered credentials for a connection. Injected (as a plain
    /// settable `var`, not an init param) so tests can drive credential
    /// selection without a live OAuth store or network provider — production
    /// wiring sets this in `AppEnvironment.bootstrapAgentSessionAndRuns`. `nil`
    /// (the default) falls back to `runConversation`'s own resolution: API-key
    /// connections build `.apiKey` credentials from `allKeys` exactly as
    /// before this task; a `.subscription` connection with no resolver has no
    /// other way to reach the OAuth store, so it fails cleanly with a re-auth
    /// message rather than silently sending no credential.
    var credentialResolver: ((Connection) async throws -> [ProviderCredential])?

    let providerFor: (Connection) -> LLMProvider
    let connections: ConnectionStore
    let config: AgentConfigStore
    let context: AgentContextService
    let registry: AgentToolRegistry
    let permissions: AgentPermissionStore
    let basePrompt: String
    let maxToolIterations: Int
    let memory: MemoryService?
    let agents: AgentStore?

    /// M7 Slice 3 (Task 10) — the per-session edit ledger consulted by
    /// `undoLastTurn()`. Additive/nil-default: with no journal injected, undo
    /// still rewinds the transcript but reports `revertedEdits: 0` (no file
    /// edits are tracked to revert), matching pre-Task-10 behavior.
    let editJournal: EditJournal?

    /// Checkpoint & Rewind Task 5 — durable capture/restore coordinator, consulted
    /// at the pre-tool interception point in `execute(_:)` (step 1, before the tool
    /// actually runs) and driven by `restoreCheckpoint(_:mode:)`/`/rewind`. `nil`
    /// (the default) means no checkpointing: `execute` skips the capture call
    /// entirely, byte-identical to pre-Task-5 behavior. Settable via
    /// `setCheckpointer(_:)` for the production `/rewind` and bootstrap wiring
    /// (Tasks 6/8), not just tests.
    var checkpointer: CheckpointCoordinator?

    /// Terminal Streaming Task 5 — the shared live-output buffer for streaming
    /// tool calls, bracketed around `registry.run(call)` in `execute(_:)` (step 3).
    /// `nil` (the default) means no streaming: `execute` skips the begin/finish
    /// calls entirely, byte-identical to pre-Task-5 behavior.
    let toolStream: ToolStreamStore?
    /// Terminal Streaming Task 5 — force-kill handle for an in-flight `run_terminal`
    /// child, consulted by `interrupt()`. `nil` (the default) means interrupt only
    /// cancels the Swift `Task`, matching pre-Task-5 behavior.
    private let terminalController: TerminalProcessController?

    /// Tool Hooks Task 4 — PreToolUse/PostToolUse hook runner, consulted at the
    /// pre-tool interception point in `execute(_:)` (step 2, after checkpoint
    /// capture but before the tool runs) and the post-tool point (step 4, after
    /// `toolStream?.finish`). `nil` (the default) means no hooks: `execute` skips
    /// both calls entirely, byte-identical to pre-Task-4 behavior.
    let hooks: ToolHookRunner?

    /// M7 Slice 3b Task 21 — the resolved `SandboxProfile.toolAllowList` for this
    /// session's trust tier (subagent/background/scheduled), when the sandbox
    /// compose layer applies. `nil` (the default) means "no sandbox layer" —
    /// byte-identical to pre-Task-21 behavior; this is the case for the main
    /// interactive session, which Slice 6 explicitly does NOT enforce here (Slice
    /// 5 owns the main session's own toolPolicy/effectiveMode composition).
    let sandboxAllowList: Set<String>?
    /// The Agent's own tool allow-list projected for `SandboxPermissionPolicy.compose`'s
    /// second layer. `nil` when `sandboxAllowList` is also nil, or when there is no
    /// extra narrowing to contribute beyond the pre-existing `agents?.active.toolPolicy`
    /// pre-check above (see `execute`'s discrepancy note).
    let agentAllowList: Set<String>?

    /// One entry per user turn, captured at the top of `send(_:)` (after the
    /// re-entrancy guard, before the user message is appended) so `/undo`/
    /// `/retry` can rewind to exactly this point. Slash-command inputs never
    /// reach this point (the command intercept above returns first), so they
    /// never create a mark.
    struct TurnMark {
        let transcriptCount: Int
        let editJournalCount: Int
        let prompt: String
    }
    var turnMarks: [TurnMark] = []

    /// M7 Slice 3 — headless runs (subagent/background/scheduled) have no
    /// approval HUD. `false` (default) preserves today's interactive behavior
    /// byte-for-byte. See `execute(_:)`'s approval branch.
    let unattended: Bool

    /// M7 Slice 5b wiring — every one of these is OPTIONAL and defaults to `nil`,
    /// mirroring the Slice 1 degrade-don't-crash pattern: with none of them injected
    /// the session behaves exactly as it did before this task (config.current model,
    /// single connection, no command interception, no usage/failover accounting).
    let router: ModelRouter?
    let usage: UsageTracker?
    let runtime: RuntimeOptionsStore?
    private let commands: CommandRegistry?
    let authProfiles: AuthProfileStore?
    /// Builds this turn's routable candidates (connection × model × catalog metadata).
    /// `@MainActor` and synchronous — live discovery (`LocalModelProbe`,
    /// `ModelCatalogService`) is async, so the provider of this closure is expected to
    /// have already cached/refreshed its candidate list elsewhere; `resolveTurn` only
    /// ever reads it once, synchronously, per turn.
    let candidatesProvider: (@MainActor () -> [RouterCandidate])?
    /// `true` when the given connection is a LOCAL server (Ollama/LM Studio/other
    /// loopback) — same rule `LocalModelProbe.isLocal` uses. Consulted only to make a
    /// terminal connection-failure message actionable (Fix 3); `nil` (host not wired,
    /// e.g. older test doubles) falls back to the generic provider message unchanged.
    let isLocalConnection: (@MainActor (Connection) -> Bool)?
    /// M7 Slice 2 seam: per-server MCP trust, keyed by the tool's namespaced name
    /// (`mcp/<server>/<tool>`). `nil` (no host wiring, or a plain non-MCP tool) means
    /// "not trusted" — see `execute`'s `isTrusted: mcpTrust?(tool.name) ?? false`. This
    /// can only ever ADD an auto-approve for an MCP tool the registry considers trusted;
    /// it never runs for the irreversible case, which `decide` always gates first.
    let mcpTrust: (@MainActor (String) -> Bool)?
    /// M7 Wave B — the ORIGINATING schedule/trigger's own saved permission
    /// posture (`SavedExecutionPosture.permissionMode`), pre-resolved to an
    /// `AgentPermissionMode` by the caller. Composed into `effectiveMode()`
    /// the same narrowing-only way as `agents?.active.permissionPosture`:
    /// it can only make a background/scheduled run MORE restrictive than the
    /// workspace's own `permissions.mode`, never less. `nil` (every pre-Wave-B
    /// call site, and the main interactive session) leaves `effectiveMode()`
    /// byte-identical to before this seam existed.
    let permissionModeOverride: AgentPermissionMode?

    enum ApprovalOutcome {
        case approved
        case approvedWithReplacement(JSONValue)
        case denied(String)
    }
    var approvalContinuation: CheckedContinuation<ApprovalOutcome, Never>?

    init(
        providerFor: @escaping (Connection) -> LLMProvider,
        connections: ConnectionStore,
        config: AgentConfigStore,
        context: AgentContextService,
        registry: AgentToolRegistry,
        permissions: AgentPermissionStore,
        basePrompt: String = AgentSession.defaultPrompt,
        maxToolIterations: Int = 25,
        memory: MemoryService? = nil,
        agents: AgentStore? = nil,
        editJournal: EditJournal? = nil,
        checkpointer: CheckpointCoordinator? = nil,
        toolStream: ToolStreamStore? = nil,
        terminalController: TerminalProcessController? = nil,
        unattended: Bool = false,
        sandboxAllowList: Set<String>? = nil,
        agentAllowList: Set<String>? = nil,
        router: ModelRouter? = nil,
        usage: UsageTracker? = nil,
        runtime: RuntimeOptionsStore? = nil,
        commands: CommandRegistry? = nil,
        authProfiles: AuthProfileStore? = nil,
        candidatesProvider: (@MainActor () -> [RouterCandidate])? = nil,
        isLocalConnection: (@MainActor (Connection) -> Bool)? = nil,
        mcpTrust: (@MainActor (String) -> Bool)? = nil,
        permissionModeOverride: AgentPermissionMode? = nil,
        hooks: ToolHookRunner? = nil
    ) {
        self.providerFor = providerFor
        self.connections = connections
        self.config = config
        self.context = context
        self.registry = registry
        self.permissions = permissions
        self.basePrompt = basePrompt
        self.maxToolIterations = maxToolIterations
        self.memory = memory
        self.agents = agents
        self.editJournal = editJournal
        self.checkpointer = checkpointer
        self.toolStream = toolStream
        self.terminalController = terminalController
        self.unattended = unattended
        self.sandboxAllowList = sandboxAllowList
        self.agentAllowList = agentAllowList
        self.router = router
        self.usage = usage
        self.runtime = runtime
        self.commands = commands
        self.authProfiles = authProfiles
        self.candidatesProvider = candidatesProvider
        self.isLocalConnection = isLocalConnection
        self.mcpTrust = mcpTrust
        self.permissionModeOverride = permissionModeOverride
        self.hooks = hooks
    }

    /// `images`, when non-empty, are attached as leading `.image` content
    /// blocks on the user message (M7 Slice 5c Task 22b — composer image
    /// drop). Defaults to `[]` so every pre-existing `send(_:)` call site
    /// (text-only) keeps compiling and behaving byte-for-byte unchanged.
    func send(_ text: String, images: [ImageAttachment] = []) {
        // Single dispatch path for slash commands (migrated from the old
        // `/remember `-only prefix intercept — see `BuiltinCommands.remember`).
        // A recognized command (including an unknown-`/foo`-surfaces-a-note case)
        // returns here without ever touching the transcript/provider path below.
        // Commands never carry images — an attached image always falls through
        // to the normal user-turn path below, even if the text happens to start
        // with `/` (there is nothing sensible for a slash command to do with it).
        if images.isEmpty, let commands {
            switch commands.run(text, on: self) {
            case .notACommand, .sendAsPrompt:
                break
            case .handled(let note):
                if let note { messages.append(AgentMessage(role: .assistant, text: note)) }
                return
            }
        }

        // Re-entrancy guard: a turn is single-flight. If one is already in
        // progress (thinking/streaming/tool/awaiting-approval), ignore the new
        // call so the in-flight Task keeps exclusive ownership of the streaming
        // buffers and transcript.
        switch state {
        case .thinking, .streaming, .callingTool, .awaitingApproval:
            return
        case .idle, .failed:
            break
        }

        // A stale hint from the previous turn must never linger into a new one.
        pendingSkillSuggestion = nil

        // Turn-boundary watermark (Task 10): captured AFTER the command
        // intercept and re-entrancy guard, so only inputs that actually start
        // a new turn get a mark — a slash command returned above, and a
        // re-entrant call while a turn is in flight bailed above too. Captured
        // BEFORE appending the user message so `transcriptCount` marks the turn's
        // first message.
        turnMarks.append(
            TurnMark(
                transcriptCount: messages.count,
                editJournalCount: editJournal?.count ?? 0,
                prompt: text))

        var content: [AgentContentBlock] = images.map { .image(mediaType: $0.mediaType, base64: $0.base64) }
        content.append(.text(text))
        messages.append(AgentMessage(role: .user, content: content))

        state = .thinking
        streamingText = ""
        streamingThinking = ""
        streamingBlocks = []

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runConversation()
        }
    }

    /// Replaces the transcript wholesale — the seam `/compact` (Task 22a) applies
    /// `TranscriptCompactor`'s output through, without giving every caller direct
    /// mutation access to `messages`.
    func replaceMessages(_ newMessages: [AgentMessage]) {
        messages = newMessages
    }

    /// Hard-interrupt the in-flight turn but KEEP the transcript, so the user can
    /// redirect with a new instruction that builds on prior context (contrast
    /// with `reset()`, which discards `messages` too). Cancels the in-flight
    /// `currentTask` and unwedges any parked approval so the loop can never be
    /// left half-parked; a subsequent `send(_:)` continues with the preserved
    /// history.
    ///
    /// Terminal Streaming Task 5: a `run_terminal` child `Process` already
    /// spawned IS force-killed here (`terminalController?.killActive()`) —
    /// task cancellation alone only discards the in-flight `Task`'s captured
    /// result when it next checks `Task.isCancelled`, it does not stop an
    /// already-spawned `Process`.
    func interrupt() {
        currentTask?.cancel()
        currentTask = nil
        terminalController?.killActive()
        if let cont = approvalContinuation {
            approvalContinuation = nil
            cont.resume(returning: .denied("interrupted"))
        }
        streamingText = ""
        streamingThinking = ""
        streamingBlocks = []
        state = .idle
        // NOTE: `messages` intentionally preserved — this is the one thing that
        // distinguishes `interrupt()` from `reset()`.
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        // Unwedge any parked approval so the in-flight loop unwinds cleanly.
        if let cont = approvalContinuation {
            approvalContinuation = nil
            cont.resume(returning: .denied("cancelled"))
        }
        messages.removeAll()
        turnMarks.removeAll()
        state = .idle
        streamingText = ""
        streamingThinking = ""
        streamingBlocks = []
        pendingSkillSuggestion = nil
    }
}
