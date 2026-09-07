import Foundation
import Observation
import AinkradHostRuntime

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

    private(set) var messages: [AgentMessage] = []
    private(set) var state: State = .idle
    private(set) var streamingText: String = ""
    private(set) var streamingThinking: String = ""

    /// Hunk ids the user has toggled to REJECT on the pending edit_file approval.
    /// Reset whenever a new approval is parked; read by `approve()` to rebuild a
    /// partial edit. Empty = accept the whole edit (unchanged behavior).
    private(set) var rejectedHunkIDs: Set<Int> = []
    func setRejectedHunkIDs(_ ids: Set<Int>) { rejectedHunkIDs = ids }

    /// Token usage accumulated from the most recently completed turn's `.usage`
    /// events. Consumed by `UsageTracker` (Task 9) to compute per-turn cost.
    private(set) var lastTurnUsage: TokenUsage = .zero

    /// The model ID actually attributed to the most recent `usage?.record(...)` call —
    /// the model failover/escalation ACTUALLY settled on, not necessarily the one
    /// `resolveTurn` originally picked. `nil` before any turn has settled.
    private(set) var lastUsageAttributedModel: String?

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

    /// Thrown when `runConversation` needs a subscription credential but no
    /// `credentialResolver` was injected — every construction site outside
    /// `bootstrapAgentSessionAndRuns`'s main session (subagent/background
    /// sessions) doesn't wire subscription OAuth yet. Caught immediately and
    /// turned into the same re-auth `.failed` message as a live store throw.
    private enum CredentialResolutionError: Error { case oauthResolverUnavailable }

    private let providerFor: (Connection) -> LLMProvider
    private let connections: ConnectionStore
    private let config: AgentConfigStore
    private let context: AgentContextService
    private let registry: AgentToolRegistry
    private let permissions: AgentPermissionStore
    private let basePrompt: String
    private let maxToolIterations: Int
    private let memory: MemoryService?
    private let agents: AgentStore?

    /// M7 Slice 3 (Task 10) — the per-session edit ledger consulted by
    /// `undoLastTurn()`. Additive/nil-default: with no journal injected, undo
    /// still rewinds the transcript but reports `revertedEdits: 0` (no file
    /// edits are tracked to revert), matching pre-Task-10 behavior.
    private let editJournal: EditJournal?

    /// Checkpoint & Rewind Task 5 — durable capture/restore coordinator, consulted
    /// at the pre-tool interception point in `execute(_:)` (step 1, before the tool
    /// actually runs) and driven by `restoreCheckpoint(_:mode:)`/`/rewind`. `nil`
    /// (the default) means no checkpointing: `execute` skips the capture call
    /// entirely, byte-identical to pre-Task-5 behavior. Settable via
    /// `setCheckpointer(_:)` for the production `/rewind` and bootstrap wiring
    /// (Tasks 6/8), not just tests.
    private var checkpointer: CheckpointCoordinator?

    /// Terminal Streaming Task 5 — the shared live-output buffer for streaming
    /// tool calls, bracketed around `registry.run(call)` in `execute(_:)` (step 3).
    /// `nil` (the default) means no streaming: `execute` skips the begin/finish
    /// calls entirely, byte-identical to pre-Task-5 behavior.
    private let toolStream: ToolStreamStore?
    /// Terminal Streaming Task 5 — force-kill handle for an in-flight `run_terminal`
    /// child, consulted by `interrupt()`. `nil` (the default) means interrupt only
    /// cancels the Swift `Task`, matching pre-Task-5 behavior.
    private let terminalController: TerminalProcessController?

    /// Tool Hooks Task 4 — PreToolUse/PostToolUse hook runner, consulted at the
    /// pre-tool interception point in `execute(_:)` (step 2, after checkpoint
    /// capture but before the tool runs) and the post-tool point (step 4, after
    /// `toolStream?.finish`). `nil` (the default) means no hooks: `execute` skips
    /// both calls entirely, byte-identical to pre-Task-4 behavior.
    private let hooks: ToolHookRunner?

    /// M7 Slice 3b Task 21 — the resolved `SandboxProfile.toolAllowList` for this
    /// session's trust tier (subagent/background/scheduled), when the sandbox
    /// compose layer applies. `nil` (the default) means "no sandbox layer" —
    /// byte-identical to pre-Task-21 behavior; this is the case for the main
    /// interactive session, which Slice 6 explicitly does NOT enforce here (Slice
    /// 5 owns the main session's own toolPolicy/effectiveMode composition).
    private let sandboxAllowList: Set<String>?
    /// The Agent's own tool allow-list projected for `SandboxPermissionPolicy.compose`'s
    /// second layer. `nil` when `sandboxAllowList` is also nil, or when there is no
    /// extra narrowing to contribute beyond the pre-existing `agents?.active.toolPolicy`
    /// pre-check above (see `execute`'s discrepancy note).
    private let agentAllowList: Set<String>?

    /// One entry per user turn, captured at the top of `send(_:)` (after the
    /// re-entrancy guard, before the user message is appended) so `/undo`/
    /// `/retry` can rewind to exactly this point. Slash-command inputs never
    /// reach this point (the command intercept above returns first), so they
    /// never create a mark.
    private struct TurnMark {
        let transcriptCount: Int
        let editJournalCount: Int
        let prompt: String
    }
    private var turnMarks: [TurnMark] = []

    /// M7 Slice 3 — headless runs (subagent/background/scheduled) have no
    /// approval HUD. `false` (default) preserves today's interactive behavior
    /// byte-for-byte. See `execute(_:)`'s approval branch.
    private let unattended: Bool

    /// M7 Slice 5b wiring — every one of these is OPTIONAL and defaults to `nil`,
    /// mirroring the Slice 1 degrade-don't-crash pattern: with none of them injected
    /// the session behaves exactly as it did before this task (config.current model,
    /// single connection, no command interception, no usage/failover accounting).
    private let router: ModelRouter?
    private let usage: UsageTracker?
    private let runtime: RuntimeOptionsStore?
    private let commands: CommandRegistry?
    private let authProfiles: AuthProfileStore?
    /// Builds this turn's routable candidates (connection × model × catalog metadata).
    /// `@MainActor` and synchronous — live discovery (`LocalModelProbe`,
    /// `ModelCatalogService`) is async, so the provider of this closure is expected to
    /// have already cached/refreshed its candidate list elsewhere; `resolveTurn` only
    /// ever reads it once, synchronously, per turn.
    private let candidatesProvider: (@MainActor () -> [RouterCandidate])?
    /// `true` when the given connection is a LOCAL server (Ollama/LM Studio/other
    /// loopback) — same rule `LocalModelProbe.isLocal` uses. Consulted only to make a
    /// terminal connection-failure message actionable (Fix 3); `nil` (host not wired,
    /// e.g. older test doubles) falls back to the generic provider message unchanged.
    private let isLocalConnection: (@MainActor (Connection) -> Bool)?
    /// M7 Slice 2 seam: per-server MCP trust, keyed by the tool's namespaced name
    /// (`mcp/<server>/<tool>`). `nil` (no host wiring, or a plain non-MCP tool) means
    /// "not trusted" — see `execute`'s `isTrusted: mcpTrust?(tool.name) ?? false`. This
    /// can only ever ADD an auto-approve for an MCP tool the registry considers trusted;
    /// it never runs for the irreversible case, which `decide` always gates first.
    private let mcpTrust: (@MainActor (String) -> Bool)?
    /// M7 Wave B — the ORIGINATING schedule/trigger's own saved permission
    /// posture (`SavedExecutionPosture.permissionMode`), pre-resolved to an
    /// `AgentPermissionMode` by the caller. Composed into `effectiveMode()`
    /// the same narrowing-only way as `agents?.active.permissionPosture`:
    /// it can only make a background/scheduled run MORE restrictive than the
    /// workspace's own `permissions.mode`, never less. `nil` (every pre-Wave-B
    /// call site, and the main interactive session) leaves `effectiveMode()`
    /// byte-identical to before this seam existed.
    private let permissionModeOverride: AgentPermissionMode?

    private enum ApprovalOutcome { case approved, approvedWithReplacement(JSONValue), denied(String) }
    private var approvalContinuation: CheckedContinuation<ApprovalOutcome, Never>?

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
        turnMarks.append(TurnMark(transcriptCount: messages.count,
                                  editJournalCount: editJournal?.count ?? 0,
                                  prompt: text))

        var content: [AgentContentBlock] = images.map { .image(mediaType: $0.mediaType, base64: $0.base64) }
        content.append(.text(text))
        messages.append(AgentMessage(role: .user, content: content))

        state = .thinking
        streamingText = ""
        streamingThinking = ""

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runConversation()
        }
    }

    /// Resume a parked approval by allowing the pending tool call to run. When
    /// `always` is true, the pending call's tool is added to the auto-approve
    /// allowlist before resuming, so future calls to it skip the HUD.
    func approve(always: Bool = false) {
        guard let cont = approvalContinuation else { return }
        if always, case .awaitingApproval(let pending) = state {
            permissions.addToAllowlist(pending.call.name)
        }
        approvalContinuation = nil
        if case .awaitingApproval(let pending) = state,
           pending.call.name == "edit_file",
           let fileDiff = pending.preview.fileDiff, !rejectedHunkIDs.isEmpty {
            let newInput = Self.rewriteEditForPartialApproval(
                input: pending.call.input, fileDiff: fileDiff, rejecting: rejectedHunkIDs)
            cont.resume(returning: .approvedWithReplacement(newInput))
        } else {
            cont.resume(returning: .approved)
        }
    }

    /// Rewrites an edit_file call so ONLY accepted hunks apply: `old_string` becomes
    /// the full original file and `new_string` the reconstructed content. Returns the
    /// input unchanged when nothing is rejected (keeps the original find/replace).
    static func rewriteEditForPartialApproval(input: JSONValue, fileDiff: FileDiff,
                                              rejecting rejected: Set<Int>) -> JSONValue {
        guard !rejected.isEmpty else { return input }
        let reconstructed = PartialEdit.reconstruct(fileDiff, rejecting: rejected)
        guard case .object(var obj) = input else { return input }
        obj["old_string"] = .string(fileDiff.original)
        obj["new_string"] = .string(reconstructed)
        return .object(obj)
    }

    /// Resume a parked approval by denying it; `reason` is fed back to the model
    /// as an error `tool_result`.
    func deny(reason: String) {
        guard let cont = approvalContinuation else { return }
        approvalContinuation = nil
        cont.resume(returning: .denied(reason))
    }

    /// Persists a user-supplied fact to memory with `.remember` provenance.
    /// Backs the `/remember <text>` command intercepted at the top of `send`.
    func remember(_ fact: String) {
        memory?.write(fact, to: .memory, provenance: .remember)
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
        state = .idle
        // NOTE: `messages` intentionally preserved — this is the one thing that
        // distinguishes `interrupt()` from `reset()`.
    }

    // MARK: - Turn undo/retry (Task 10)

    /// Reverts the last user turn: its file edits (via `EditJournal.revertEntries(after:)`)
    /// AND the transcript (truncated back to before the turn's user message).
    ///
    /// **All-or-nothing:** if the removed turn executed any tool classified as
    /// irreversible (`TurnUndo.classifyIrreversible`, e.g. `run_terminal`/`mcp/*` —
    /// a shell command or a git push already happened and cannot be unwound), the
    /// WHOLE undo is refused: no file edit is reverted, the transcript is left
    /// untouched, and the turn mark stays on the stack. Silently reverting only the
    /// file-edit half of a turn while leaving an irreversible side effect unmentioned
    /// would misrepresent what actually happened, so refusal is the only honest move.
    ///
    /// Calling this repeatedly walks back turn-by-turn (each successful call pops
    /// exactly one mark). With no turn to undo, returns a zero/empty summary — a
    /// no-op, not an error.
    @discardableResult
    func undoLastTurn() -> TurnUndoSummary {
        guard let mark = turnMarks.last else {
            return TurnUndoSummary(revertedEdits: 0, irreversible: [])
        }

        let start = min(mark.transcriptCount, messages.count)
        let removedTurn = Array(messages.suffix(from: start))
        let irreversible = TurnUndo.classifyIrreversible(removedTurn)
        guard irreversible.isEmpty else {
            // Refuse entirely — nothing reverted, mark left in place.
            return TurnUndoSummary(revertedEdits: 0, irreversible: irreversible)
        }

        turnMarks.removeLast()
        let reverted = editJournal?.revertEntries(after: mark.editJournalCount) ?? 0
        // PROVISIONAL (Slice 1): revert memory writes recorded during this turn once
        // the Slice 1 log exposes a count-based "undo entries after N" hook.
        // memory?.log.undoEntries(after: mark.memoryLogCount)
        if mark.transcriptCount <= messages.count {
            messages.removeLast(messages.count - mark.transcriptCount)
        }
        return TurnUndoSummary(revertedEdits: reverted, irreversible: [])
    }

    /// Re-submits the last user turn's prompt: undoes it first (so a retry doesn't
    /// pile a second attempt's transcript/edits on top of the first), then sends
    /// the same prompt again. If the last turn is irreversible, `undoLastTurn()`
    /// refuses (see above) and this simply resends the prompt as a NEW turn on top
    /// of the existing transcript — retry never discards an irreversible turn's
    /// history, it just doesn't get a "clean" rewind first.
    func retryLastTurn() {
        guard let prompt = turnMarks.last?.prompt else { return }
        _ = undoLastTurn()
        send(prompt)
    }

    /// Restores workspace state (and, for `.conversation`/`.both`, truncates the
    /// transcript back to the checkpoint's turn boundary). The durable-checkpoint
    /// counterpart to `undoLastTurn()`, driven by `/rewind` (Task 6). Returns the
    /// `CheckpointCoordinator.RestoreOutcome` (`nil` when no checkpointer is wired)
    /// so callers (`/rewind`) can surface a restore failure instead of silently
    /// swallowing it — see `CheckpointCoordinator.RestoreOutcome`.
    @discardableResult
    func restoreCheckpoint(_ checkpoint: Checkpoint, mode: CheckpointCoordinator.RestoreMode) async -> CheckpointCoordinator.RestoreOutcome? {
        guard let checkpointer else { return nil }
        let outcome = await checkpointer.restore(checkpoint, mode: mode)
        let truncateTo = outcome.transcriptIndex
        if truncateTo >= 0, truncateTo <= messages.count {
            let cut = cleanTranscriptBoundary(upTo: truncateTo)
            messages.removeLast(messages.count - cut)
        }
        return outcome
    }

    /// Finds the closest safe cut index at-or-before `target` that never leaves a
    /// dangling `tool_use` at the end of the truncated transcript. `Checkpoint.
    /// transcriptIndex` is captured AFTER the assistant message carrying a
    /// `tool_use` block was appended but BEFORE its `tool_result` (the pre-tool
    /// interception point in `execute(_:)`) — truncating to exactly that index
    /// would leave a trailing assistant message with an unmatched `tool_use`,
    /// which the next provider `send` rejects. Walks backward past any such
    /// trailing assistant message(s) until the cut lands on a clean boundary (a
    /// user message, or an assistant message with no dangling `tool_use`).
    private func cleanTranscriptBoundary(upTo target: Int) -> Int {
        var cut = max(0, min(target, messages.count))
        while cut > 0 {
            let last = messages[cut - 1]
            guard last.role == .assistant,
                  last.content.contains(where: { if case .toolUse = $0 { return true }; return false })
            else { break }
            cut -= 1
        }
        return cut
    }

    /// Appends a system-authored note to the transcript outside of a normal turn —
    /// used by `/rewind`'s async restore `Task` (Fix #2) to surface a restore
    /// failure that only becomes known after the command handler already returned
    /// its synchronous "in progress" note.
    func appendSystemNote(_ text: String) {
        messages.append(AgentMessage(role: .assistant, text: text))
    }

    /// Production `/rewind` and bootstrap wiring (Tasks 6/8) call these — not
    /// test-only despite the historically test-flavored name pattern elsewhere
    /// in this file.
    func setCheckpointer(_ c: CheckpointCoordinator) { checkpointer = c }
    func activeCheckpointer() -> CheckpointCoordinator? { checkpointer }

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
        pendingSkillSuggestion = nil
    }

    // MARK: - Model resolution (Task 16)

    /// One turn's resolved sending target: which connection/model to use, the
    /// `RouterDecision` that produced it (`nil` when the router path wasn't taken —
    /// no router injected, or no candidates available), and the premium baseline
    /// the router avoided (feeds `UsageTracker`'s savings math).
    struct ResolvedTurn: Sendable {
        let connection: Connection?
        let modelConfig: AgentModelConfig
        let tier: ModelTier
        let baselineModel: String?
        let decision: RouterDecision?
        var model: String { modelConfig.model }
    }

    /// Resolution order: session pin (`/model`) → router (bounded by the active
    /// Agent's routing envelope; a disabled router or an unmatched pin falls back to
    /// the first candidate) → Agent default model → the standing `AgentConfigStore`
    /// model. The router path is OPT-IN: it only runs when both a `router` is
    /// injected AND `candidatesProvider` yields at least one candidate — with either
    /// missing, resolution degrades to the pre-Task-16 pin/default/config chain.
    private func resolveTurn() async -> ResolvedTurn {
        let pin = runtime?.options.pinnedModel
        var candidates = candidatesProvider?() ?? []

        // An explicit pin is an explicit override and MUST be honorable even when it
        // isn't in the preset-derived candidate list — e.g. a live-discovered model
        // id (an OpenRouter/Ollama model the user selected) that no `curatedModels`
        // enumerates. Without this, the router can't match the pin (it matches by
        // `candidate.model == pin`) and silently free-first routes to some OTHER
        // connection's free model. Synthesize a candidate for the pin on the ACTIVE
        // connection so the router's pin-match resolves it on the connection the user
        // actually chose. Uses the same conservative descriptor `candidatesProvider`
        // falls back to for a model the catalog doesn't recognize.
        if let pin, !candidates.contains(where: { $0.model == pin }), let active = activeConnection() {
            candidates.insert(RouterCandidate(
                connectionID: active.id, model: pin,
                descriptor: ModelDescriptor(id: pin, tier: .cheapPaid, contextWindow: 128_000, capabilities: [.toolUse])),
                at: 0)
        }

        if let router, !candidates.isEmpty {
            let routing = agents?.active.routing ?? AgentRouting()
            let lastMessage = messages.last(where: { $0.role == .user })?.text ?? ""
            // `needsTools` signals that THIS turn requires tool-use capability, not
            // merely that the registry has tools available (nearly always true for an
            // agentic host) — without deeper message-intent analysis, the conservative
            // default is `false`, so a plain/trivial message can still free-first route
            // to a local model even though tools exist in the registry.
            let signal = TaskSignal(estimatedInputTokens: lastMessage.count / 4,
                                    needsVision: false, needsTools: false,
                                    reasoningHeavy: false)
            let request = RouterRequest(signal: signal, lastMessage: lastMessage, routing: routing,
                                        candidates: candidates, userPinnedModel: pin, attempt: 0)
            let decision = await router.route(request)
            let connection = connections.connections.first(where: { $0.id == decision.candidate.connectionID })
                ?? activeConnection()
            let effort = effortString(capabilities: decision.candidate.descriptor.capabilities)
            return ResolvedTurn(connection: connection,
                                modelConfig: AgentModelConfig(model: decision.candidate.model, effort: effort),
                                tier: decision.tier, baselineModel: decision.baselineModel, decision: decision)
        }

        // Degraded path (no router, or no candidates to route over): pin, else the
        // active Agent's default, else the standing config model — exactly the
        // pre-Task-16 behavior when `agents`/`runtime` are also both nil.
        let fallbackModel = pin ?? agents?.active.defaultModel ?? config.current.model
        let connection = activeConnection()
        return ResolvedTurn(connection: connection,
                            modelConfig: AgentModelConfig(model: fallbackModel, effort: config.current.effort),
                            tier: .premium, baselineModel: nil, decision: nil)
    }

    /// `/think`'s honest-scope check (and `resolveTurn`'s effort wiring) both need
    /// "does this model actually respect an effort dial" — only `ClaudeProvider` sends
    /// `output_config.effort`; other kinds ignore it. `capabilities: nil` (the degraded
    /// resolution path, where there is no descriptor) is treated as capable, matching
    /// pre-Task-16 behavior of always honoring `config.current.effort` unconditionally.
    private func effortString(capabilities: ModelCapability?) -> String {
        guard let capabilities, capabilities.contains(.reasoningEffort) else { return config.current.effort }
        switch runtime?.options.thinkLevel {
        case "low": return "low"
        case "medium": return "medium"
        case "high": return "high"
        case "max": return "xhigh"
        default: return config.current.effort
        }
    }

    /// Best-effort "what model is this session currently pointed at" for slash
    /// commands (`/think`'s capability notice) — NOT a substitute for `resolveTurn`,
    /// which also consults the router; this is synchronous and router-unaware.
    func activeModelIDForCommands() -> String {
        runtime?.options.pinnedModel ?? agents?.active.defaultModel ?? config.current.model
    }

    /// Models to walk on a retryable send failure: the resolved model first, then any
    /// other candidate on the SAME connection (failover swaps model/key, never
    /// connection — see `FailoverController`'s doc comment on the `(model, keyIndex)`
    /// ordering it assumes).
    private func failoverModels(primary: String, connectionID: UUID) -> [String] {
        guard let candidatesProvider else { return [primary] }
        var ordered = [primary]
        for candidate in candidatesProvider() where candidate.connectionID == connectionID {
            if !ordered.contains(candidate.model) { ordered.append(candidate.model) }
        }
        return ordered
    }

    /// Records the turn's actual outcome — the model failover/escalation ACTUALLY
    /// used, not just the one `resolveTurn` originally picked — into the router's
    /// learning store and the usage ledger. Called once per settle (both the
    /// `.completed` and `.failed` exits of `runConversation`).
    private func recordSettlement(success: Bool, resolved: ResolvedTurn, usedModel: String) {
        if let decision = resolved.decision {
            let effective = decision.candidate.model == usedModel ? decision
                : RouterDecision(candidate: RouterCandidate(connectionID: decision.candidate.connectionID,
                                                            model: usedModel, descriptor: decision.candidate.descriptor),
                                 tier: decision.tier, reason: decision.reason,
                                 escalated: decision.escalated, baselineModel: decision.baselineModel)
            router?.recordOutcome(effective, success: success)
        }
        usage?.record(model: usedModel, usage: lastTurnUsage, baselineModel: resolved.baselineModel)
        lastUsageAttributedModel = usedModel
    }

    // MARK: - Loop

    private func runConversation() async {
        var iterations = 0
        let resolved = await resolveTurn()
        guard let connection = resolved.connection else {
            state = .failed("No connection configured. Add one in Sage settings.")
            return
        }
        let allKeys = authProfiles?.keys(for: connection) ?? (connections.token(for: connection).map { [$0] } ?? [])
        if connection.authMode == .apiKey,
           ProviderPreset.preset(id: connection.presetID).requiresKey, allKeys.isEmpty {
            state = .failed("No API key configured for \(connection.displayName)")
            return
        }

        let credentials: [ProviderCredential]
        do {
            if let resolver = credentialResolver {
                credentials = try await resolver(connection)
            } else if connection.authMode == .subscription {
                throw CredentialResolutionError.oauthResolverUnavailable
            } else {
                credentials = (allKeys.isEmpty ? [""] : allKeys).map { .apiKey($0) }
            }
        } catch {
            state = .failed("Your Claude subscription needs to be re-authorized. " +
                            "Open Sage settings and sign in again.")
            return
        }
        // A resolver that yields no credentials would otherwise crash the subscript below.
        guard let firstCredential = credentials.first else {
            state = .failed("No credentials available for \(connection.displayName).")
            return
        }

        let contextBlock = context.assembleContext()
        let agentInstructions = agents?.active.instructions ?? ""
        let promptHead = agentInstructions.isEmpty ? basePrompt : basePrompt + "\n\n" + agentInstructions
        let system = contextBlock.isEmpty ? promptHead : promptHead + "\n\n" + contextBlock
        let provider = providerFor(connection)

        var currentModel = resolved.modelConfig
        var currentCredential = firstCredential
        var didOpeningFailover = false

        while true {
            // Cooperative cancellation: `reset()` cancels this task (and unwedges
            // any parked approval). Bail BEFORE re-sending so a reset never spawns
            // a zombie turn that resurrects the just-cleared transcript.
            if Task.isCancelled { return }

            let outcome: TurnOutcome
            if !didOpeningFailover {
                let models = failoverModels(primary: currentModel.model, connectionID: connection.id)
                let (result, usedModel, usedCredential) = await runOneTurnWithFailover(
                    provider: provider, system: system, model: currentModel, models: models, credentials: credentials)
                outcome = result
                currentModel = AgentModelConfig(model: usedModel, effort: currentModel.effort)
                currentCredential = usedCredential
                didOpeningFailover = true
            } else {
                outcome = await runOneTurn(provider: provider, system: system, model: currentModel, credential: currentCredential)
            }

            switch outcome {
            case .failed(let message):
                streamingText = ""
                streamingThinking = ""
                let isLocal = isLocalConnection?(connection) ?? false
                state = .failed(Self.actionableFailureMessage(message, connection: connection, isLocal: isLocal))
                recordSettlement(success: false, resolved: resolved, usedModel: currentModel.model)
                return
            case .completed:
                streamingText = ""
                streamingThinking = ""
                state = .idle
                recordSettlement(success: true, resolved: resolved, usedModel: currentModel.model)
                settled()
                return
            case .toolCalls(let calls, let assistantText, let thinking):
                iterations += 1
                if iterations > maxToolIterations {
                    messages.append(AgentMessage(role: .assistant,
                        text: (assistantText.isEmpty ? "" : assistantText + "\n\n") +
                              "Stopped: reached the \(maxToolIterations)-step tool limit."))
                    state = .idle
                    settled()
                    return
                }
                // Commit the assistant turn (thinking + text + tool_use blocks).
                var assistantBlocks: [AgentContentBlock] = []
                if !thinking.isEmpty { assistantBlocks.append(.thinking(thinking)) }
                if !assistantText.isEmpty { assistantBlocks.append(.text(assistantText)) }
                assistantBlocks.append(contentsOf: calls.map { .toolUse(id: $0.id, name: $0.name, input: $0.input) })
                messages.append(AgentMessage(role: .assistant, content: assistantBlocks))

                // Execute each call behind the gate; gather results into one user turn.
                var resultBlocks: [AgentContentBlock] = []
                for call in calls {
                    let result = await execute(call)
                    // A reset during a parked approval cancels this task while
                    // suspended inside `execute`. Bail before recording the
                    // (denied) result so `messages` stays cleared and `.idle` holds.
                    if Task.isCancelled { return }
                    resultBlocks.append(.toolResult(toolUseID: call.id, content: result.content, isError: result.isError))
                }
                messages.append(AgentMessage(role: .user, content: resultBlocks))
                streamingText = ""
                streamingThinking = ""
                // loop: re-send with the appended results
            }
        }
    }

    /// Turns a generic connection-failure message into an actionable one when the
    /// failing connection is LOCAL (Ollama/LM Studio/other loopback) — the common
    /// case being the server just isn't running, which the generic provider message
    /// ("Streaming failed: Could not connect to the server.") gives the user no way
    /// to act on. Any other failure (remote provider, or a local-connection failure
    /// that isn't connectivity-shaped, e.g. an auth error) passes through unchanged.
    /// Pure/testable: no I/O, no actor isolation required.
    nonisolated static func actionableFailureMessage(_ message: String, connection: Connection, isLocal: Bool) -> String {
        guard isLocal, message.lowercased().contains("connect") else { return message }
        return "Can't reach the local model server at \(connection.baseURL). " +
               "Start Ollama/LM Studio, or switch models (pick a model in the picker or /model <id>)."
    }

    private enum TurnOutcome {
        case completed
        case failed(String)
        case toolCalls([ToolCall], assistantText: String, thinking: String)
    }

    private func runOneTurn(provider: LLMProvider, system: String,
                            model: AgentModelConfig, credential: ProviderCredential) async -> TurnOutcome {
        let signpost = AinkradSignposts.begin(AinkradSignposts.agent, "agent-turn")
        defer { AinkradSignposts.end(AinkradSignposts.agent, "agent-turn", signpost) }
        state = .thinking
        streamingText = ""
        streamingThinking = ""
        var pendingCalls: [ToolCall] = []
        var failure: String?
        var sawDone = false
        var turnUsage = TokenUsage.zero

        let stream = provider.send(messages: messages, system: system,
                                   tools: allowedSchemas(), model: model, credential: credential)
        do {
            for try await event in stream {
                switch event {
                case .thinkingDelta(let d): streamingThinking += d; if state != .thinking { state = .thinking }
                case .textDelta(let d): streamingText += d; if state != .streaming { state = .streaming }
                case .toolUseStart(_, let name): state = .callingTool(name)
                case .toolInputDelta: break
                case .toolUseComplete(let id, let name, let input):
                    pendingCalls.append(ToolCall(id: id, name: name, input: input))
                case .done: sawDone = true
                case .usage(let u): turnUsage = turnUsage + u
                case .failed(let m): failure = m
                }
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        lastTurnUsage = turnUsage

        if let failure { return .failed(failure) }
        if !pendingCalls.isEmpty {
            return .toolCalls(pendingCalls, assistantText: streamingText, thinking: streamingThinking)
        }
        // No tool calls: commit any assistant text (with leading thinking), then settle.
        if !streamingText.isEmpty {
            var blocks: [AgentContentBlock] = []
            if !streamingThinking.isEmpty { blocks.append(.thinking(streamingThinking)) }
            blocks.append(.text(streamingText))
            messages.append(AgentMessage(role: .assistant, content: blocks))
            return .completed
        }
        // Empty text. A clean `.done` (tool-less/text-less end_turn) settles to
        // idle; a stream that ended WITHOUT `.done` is a wedge we finalize as a
        // failure so the re-entrancy guard never stays stuck.
        return sawDone ? .completed : .failed("The response ended unexpectedly.")
    }

    /// Wraps the FIRST HTTP call of a user turn in a bounded failover walk over
    /// `models × keys`, advancing via `FailoverController.nextAttempt` (the same pure
    /// step function `FailoverController.run` uses) on a retryable failure — see
    /// `FailoverController.classify`. A non-retryable content/user error returns
    /// immediately (no cycling through every candidate for an error that would fail
    /// identically against all of them). Driven manually here, rather than through
    /// `FailoverController.run`'s closure-based driver, because that generic static
    /// function isn't actor-isolated — handing it a `@MainActor`-capturing closure
    /// (this method needs `self.runOneTurn`) trips Swift 6's strict-concurrency
    /// sending check. The bound (`models.count * keys.count` attempts, mirroring
    /// `run`'s own bound) is enforced identically. Follow-up tool-loop iterations
    /// within the same turn do NOT re-run failover — they reuse whichever `(model,
    /// key)` this call settled on.
    private func runOneTurnWithFailover(
        provider: LLMProvider, system: String, model: AgentModelConfig,
        models: [String], credentials: [ProviderCredential]
    ) async -> (TurnOutcome, model: String, credential: ProviderCredential) {
        let keys = credentials.map { _ in "" }
        guard var current = FailoverController.nextAttempt(
            models: models, keys: keys, failedModel: nil, failedKeyIndex: nil, errorKind: .providerError
        ) else {
            return (.failed("no candidates configured"), model.model, credentials.first ?? .apiKey(""))
        }

        let maxAttempts = max(models.count * credentials.count, 1)
        var lastOutcome: TurnOutcome = .failed("no candidates configured")
        for _ in 0..<maxAttempts {
            let attemptModel = AgentModelConfig(model: current.model, effort: model.effort)
            let outcome = await runOneTurn(provider: provider, system: system,
                                           model: attemptModel, credential: credentials[current.keyIndex])
            guard case .failed(let message) = outcome, let kind = FailoverController.classify(message) else {
                return (outcome, current.model, credentials[current.keyIndex])
            }
            lastOutcome = outcome
            guard let next = FailoverController.nextAttempt(
                models: models, keys: keys,
                failedModel: current.model, failedKeyIndex: current.keyIndex, errorKind: kind
            ) else {
                return (outcome, current.model, credentials[current.keyIndex])
            }
            current = next
        }
        return (lastOutcome, current.model, credentials[current.keyIndex])
    }

    private func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return ToolResult(content: "Unknown tool: \(call.name)", isError: true)
        }

        // Agent tool-policy pre-check, BEFORE the permission gate: this only
        // ever narrows — it can reject a call the gate would have allowed, but
        // can never approve one the gate would have blocked.
        if let policy = agents?.active.toolPolicy,
           !policy.allows(toolName: tool.name, permission: tool.permission) {
            return ToolResult(
                content: "The active agent (\(agents?.active.name ?? "")) is not permitted to use \(tool.name).",
                isError: true)
        }

        var decision = AgentPermissionPolicy.decide(
            toolPermission: tool.permission, toolName: tool.name,
            mode: effectiveMode(), allowlist: permissions.allowlist,
            gateReads: permissions.gateReads, isIrreversible: tool.isIrreversible(call.input),
            isTrusted: mcpTrust?(tool.name) ?? false)

        // M7 Slice 3b Task 21 — the sandbox compose layer, ONLY for autonomous run
        // sessions (subagent/background/scheduled — every one that's constructed
        // with a non-nil `sandboxAllowList`). Narrowing-only: `.denied` short-
        // circuits before the tool ever runs; `.requireApproval` re-enters the
        // existing gate below (which auto-denies for an unattended run, Task 8);
        // `.autoApprove` proceeds. A nil `sandboxAllowList` (every pre-Task-21
        // call site, and the main interactive session) skips this branch
        // entirely — byte-identical to before this task.
        if let sandboxAllowList {
            let explanation = SandboxPermissionPolicy.compose(
                gate: decision, agentAllowList: agentAllowList,
                sandboxAllowList: sandboxAllowList, toolName: tool.name)
            switch explanation.effective {
            case .denied:
                return ToolResult(content: "Blocked by sandbox: \(explanation.reason)", isError: true)
            case .requireApproval:
                decision = .requireApproval
            case .autoApprove:
                decision = .autoApprove
            }
        }

        // The call actually run below. A partial-hunk approval rewrites the
        // edit_file input (accepted hunks only) but MUST still flow through the
        // shared pre-tool seam (checkpoint → PreToolUse → stream → PostToolUse),
        // so we rebind here and fall through rather than running it early.
        var effectiveCall = call

        if decision == .requireApproval {
            // Unattended gate (M7 Slice 3): a headless run (subagent/background/
            // scheduled) has no HUD to resolve an approval, so parking on the
            // continuation here would wedge the run forever. `decide`'s verdict
            // is untouched — this only changes how the SESSION handles a
            // `.requireApproval` it gets back: auto-deny instead of awaiting a
            // human. This can only narrow (deny more), never approve something
            // the gate itself would have blocked — no privilege escalation.
            guard !unattended else {
                return ToolResult(
                    content: "Blocked: \(call.name) requires approval and this run is unattended.",
                    isError: true)
            }
            let preview = tool.approvalPreview(call.input)
            rejectedHunkIDs = []            // fresh selection per approval
            state = .awaitingApproval(PendingApproval(call: call, preview: preview))
            let outcome = await withCheckedContinuation { (cont: CheckedContinuation<ApprovalOutcome, Never>) in
                approvalContinuation = cont
            }
            if case .denied(let reason) = outcome {
                return ToolResult(content: reason, isError: true)
            }
            if case .approvedWithReplacement(let newInput) = outcome {
                // Apply only accepted hunks — but still run through the shared
                // seam below so the checkpoint/hooks/streaming fire exactly as
                // they do for a whole-file approval.
                effectiveCall = ToolCall(id: call.id, name: call.name, input: newInput)
            }
        }

        state = .callingTool(effectiveCall.name)
        // Pre-tool interception point (shared seam): step 1 — durable checkpoint before a mutating tool.
        await checkpointer?.captureIfMutating(call: effectiveCall, tool: tool)
        // step 2 — PreToolUse hooks: a non-zero hook blocks the call before it runs.
        if let block = await hooks?.runPreToolUse(effectiveCall) { return block }
        // step 3 — terminal-streaming: bracket the tool run so the live card fills.
        toolStream?.begin(effectiveCall.id)
        let result = await registry.run(effectiveCall)
        toolStream?.finish(effectiveCall.id, finalOutput: result.content)
        // step 4 — PostToolUse hooks: post-process a successful result (format/lint note).
        return await hooks?.runPostToolUse(effectiveCall, result: result) ?? result
    }

    /// Runs the cheap rule-based consolidation pass and notifies observers
    /// whenever a turn settles to `.idle` (both terminal points inside
    /// `runConversation` — not `reset()`, which is a discard, not a settle).
    private func settled() {
        if let memory { MemoryConsolidator.consolidate(memory) }
        updateSkillSuggestion(from: messages, succeeded: { if case .idle = state { return true } else { return false } }())
        onSettled?()
    }

    /// The active connection: the configured one, else the first connection.
    private func activeConnection() -> Connection? {
        if let id = config.activeConnectionID,
           let match = connections.connections.first(where: { $0.id == id }) {
            return match
        }
        return connections.connections.first
    }

    /// Tool schemas presented to the provider, filtered to the active Agent's
    /// tool policy — a Plan Agent must not even SEE `edit_file` in its tool
    /// list. Narrows only: with no active `agents` store, every registry
    /// schema is presented, unchanged from pre-Task-4 behavior.
    private func allowedSchemas() -> [AgentToolSchema] {
        guard let policy = agents?.active.toolPolicy else { return registry.schemas }
        return registry.schemas.filter { schema in
            guard let tool = registry.tool(named: schema.name) else { return false }
            return policy.allows(toolName: tool.name, permission: tool.permission)
        }
    }

    /// Restrictiveness order for `AgentPermissionMode`, used by `effectiveMode()`
    /// to compute the most-restrictive-wins composition. Higher = more permissive.
    private static func rank(_ mode: AgentPermissionMode) -> Int {
        switch mode {
        case .ask: return 0
        case .autoApprove: return 1
        case .fullAuto: return 2
        }
    }

    /// The permission mode actually passed to `AgentPermissionPolicy.decide`:
    /// the MOST restrictive of the workspace mode, the active Agent's
    /// `permissionPosture` (when set), and `permissionModeOverride` (when set,
    /// M7 Wave B — a schedule/trigger's own saved posture). Each seam can only
    /// tighten the gate further; neither can ever loosen it beyond the
    /// workspace's own mode, and composing both narrows at least as much as
    /// either alone.
    private func effectiveMode() -> AgentPermissionMode {
        var mode = permissions.mode
        if let posture = agents?.active.permissionPosture, Self.rank(posture) < Self.rank(mode) {
            mode = posture
        }
        if let override = permissionModeOverride, Self.rank(override) < Self.rank(mode) {
            mode = override
        }
        return mode
    }

    // MARK: - Test hooks (internal; exercised via @testable import in AinkradTests)

    func executeForTesting(_ call: ToolCall) async -> ToolResult { await execute(call) }
    func allowedSchemasForTesting() -> [AgentToolSchema] { allowedSchemas() }
    func effectiveModeForTesting() -> AgentPermissionMode { effectiveMode() }
    func resolveTurnForTesting() async -> ResolvedTurn { await resolveTurn() }
    /// M7 Slice 3 Task 11 — proves the production subagent/background `makeSession`
    /// seam actually built the child `unattended: true`.
    var unattendedForTesting: Bool { unattended }
}
