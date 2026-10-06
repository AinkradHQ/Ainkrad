import Foundation

extension AgentSession {
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
    func restoreCheckpoint(_ checkpoint: Checkpoint, mode: CheckpointCoordinator.RestoreMode) async
        -> CheckpointCoordinator.RestoreOutcome?
    {
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
                last.content.contains(where: {
                    if case .toolUse = $0 { return true }
                    return false
                })
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
}
