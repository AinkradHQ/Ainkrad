// Sources/Ainkrad/Core/AgentKit/Hooks/ToolHookRunner.swift
import Foundation

/// Runs matched user hooks around a tool call, through the SAME
/// `ExecutionRouter`/`HostBackend` path `RunTerminalTool` uses (`.mainInteractive`).
/// A PreToolUse hook that exits non-zero BLOCKS the call (its combined output
/// becomes the denial fed back to the model). PostToolUse hooks run after the
/// tool succeeds; their output is appended to the tool result as an advisory note.
/// Tool-call context is exported to the hook as env vars.
@MainActor
final class ToolHookRunner {
    private let store: ToolHooksStore
    private let router: ExecutionRouter
    private let workingDir: @MainActor () -> String

    init(store: ToolHooksStore, router: ExecutionRouter, workingDir: @escaping @MainActor () -> String) {
        self.store = store
        self.router = router
        self.workingDir = workingDir
    }

    func runPreToolUse(_ call: ToolCall) async -> ToolResult? {
        for hook in store.hooks(for: .preToolUse, toolName: call.name) {
            guard let outcome = await run(hook, call: call) else { continue }  // router failure => don't block
            if outcome.isError {
                return ToolResult(
                    content: "Blocked by PreToolUse hook (match \(hook.match)):\n\(outcome.output)",
                    isError: true)
            }
        }
        return nil
    }

    func runPostToolUse(_ call: ToolCall, result: ToolResult) async -> ToolResult {
        guard !result.isError else { return result }  // don't post-process a failed call
        var notes: [String] = []
        for hook in store.hooks(for: .postToolUse, toolName: call.name) {
            if let outcome = await run(hook, call: call), !outcome.output.isEmpty {
                notes.append(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        guard !notes.isEmpty else { return result }
        return ToolResult(content: result.content + "\n\n[hooks]\n" + notes.joined(separator: "\n"), isError: false)
    }

    /// Runs one hook, injecting the tool-call context as `AINKRAD_*` env vars via
    /// an exported prefix on the shell line (the command line is the only input
    /// channel `ExecutionRequest` carries). Values are shell-quoted so
    /// model-influenced content (e.g. a path/command) can never break out of the
    /// quoting and execute as shell syntax.
    private func run(_ hook: ToolHook, call: ToolCall) async -> ExecutionResult? {
        guard let (backend, profileBase) = try? await router.route(tier: .mainInteractive, policy: nil) else {
            return nil
        }
        var profile = profileBase
        profile.resourceLimits.timeoutSeconds = hook.timeoutSeconds
        let name = call.name
        let path = call.input["path"]?.stringValue ?? ""
        let command = call.input["command"]?.stringValue ?? ""
        let exported =
            "export AINKRAD_TOOL_NAME=\(shellQuote(name)) "
            + "AINKRAD_TOOL_PATH=\(shellQuote(path)) "
            + "AINKRAD_TOOL_COMMAND=\(shellQuote(command)); "
        let line = exported + hook.command
        return try? await backend.run(ExecutionRequest(command: line, workingDir: workingDir(), profile: profile))
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
