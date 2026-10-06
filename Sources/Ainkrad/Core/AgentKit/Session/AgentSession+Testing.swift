import Foundation

extension AgentSession {
    // MARK: - Test hooks (internal; exercised via @testable import in AinkradTests)

    func executeForTesting(_ call: ToolCall) async -> ToolResult { await execute(call) }
    func allowedSchemasForTesting() -> [AgentToolSchema] { allowedSchemas() }
    func effectiveModeForTesting() -> AgentPermissionMode { effectiveMode() }
    func resolveTurnForTesting() async -> ResolvedTurn { await resolveTurn() }
    /// M7 Slice 3 Task 11 — proves the production subagent/background `makeSession`
    /// seam actually built the child `unattended: true`.
    var unattendedForTesting: Bool { unattended }
}
