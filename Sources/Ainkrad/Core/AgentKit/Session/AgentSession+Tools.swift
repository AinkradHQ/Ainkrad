import Foundation

extension AgentSession {
    func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return ToolResult(content: "Unknown tool: \(call.name)", isError: true)
        }

        // Agent tool-policy pre-check, BEFORE the permission gate: this only
        // ever narrows — it can reject a call the gate would have allowed, but
        // can never approve one the gate would have blocked.
        if let policy = agents?.active.toolPolicy,
            !policy.allows(toolName: tool.name, permission: tool.permission)
        {
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
            rejectedHunkIDs = []  // fresh selection per approval
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
    func settled() {
        if let memory { MemoryConsolidator.consolidate(memory) }
        updateSkillSuggestion(
            from: messages, succeeded: { if case .idle = state { return true } else { return false } }())
        onSettled?()
    }

    /// The active connection: the configured one, else the first connection.
    func activeConnection() -> Connection? {
        if let id = config.activeConnectionID,
            let match = connections.connections.first(where: { $0.id == id })
        {
            return match
        }
        return connections.connections.first
    }

    /// Tool schemas presented to the provider, filtered to the active Agent's
    /// tool policy — a Plan Agent must not even SEE `edit_file` in its tool
    /// list. Narrows only: with no active `agents` store, every registry
    /// schema is presented, unchanged from pre-Task-4 behavior.
    func allowedSchemas() -> [AgentToolSchema] {
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
    func effectiveMode() -> AgentPermissionMode {
        var mode = permissions.mode
        if let posture = agents?.active.permissionPosture, Self.rank(posture) < Self.rank(mode) {
            mode = posture
        }
        if let override = permissionModeOverride, Self.rank(override) < Self.rank(mode) {
            mode = override
        }
        return mode
    }
}
