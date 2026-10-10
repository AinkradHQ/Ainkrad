import AinkradHostRuntime
import Foundation
import AinkradAppKit

extension AgentSession {
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
            let fileDiff = pending.preview.fileDiff, !rejectedHunkIDs.isEmpty
        {
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
    static func rewriteEditForPartialApproval(
        input: JSONValue, fileDiff: AinkradFileDiff,
        rejecting rejected: Set<Int>
    ) -> JSONValue {
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
}
