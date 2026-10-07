import Foundation

/// The result of executing an `AgentRun`'s prompt to completion.
enum AgentRunOutcome: Sendable {
    case success(String)
    case failure(String)
}

/// Executes a run's prompt to completion, streaming log lines back. The
/// production impl drives a headless `AgentSession` (Task 6 / Task 11 wiring);
/// tests inject a stub.
@MainActor
protocol AgentRunRunner: AnyObject {
    /// `posture` is the ORIGINATING schedule/trigger's saved execution posture
    /// (M7 Wave B) — `nil` for plain `.chat` runs. A conformer projects it into
    /// the session it builds (permission mode narrowing + sandbox profile);
    /// it must never be used to WIDEN beyond whatever the conformer would have
    /// used with no posture at all.
    func execute(
        prompt: String, posture: SavedExecutionPosture?,
        appendLog: @escaping (String) -> Void
    ) async -> AgentRunOutcome
}
