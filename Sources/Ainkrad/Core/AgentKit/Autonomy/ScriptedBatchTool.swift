import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Autonomy/ScriptedBatchTool.swift
import Foundation

/// `AgentTool` that batches multiple steps into one sandboxed script run
/// (collapses a multi-step pipeline into a single pass), routed through
/// Slice 6's `ExecutionRouter`. Disabled entirely when no router is injected
/// (host build before Slice 6 lands, or a deployment without a sandbox
/// backend configured) — it never falls back to running the script
/// unsandboxed.
///
/// DEFERRED (fast-follow, do NOT build here): the "tools via RPC" bridge that
/// would let the script call back into host tools through the permission
/// gate mid-execution. That needs a stdin/stdout control protocol plus
/// backend cooperation that doesn't exist yet. Until then, a script may only
/// run shell inside the sandbox — it cannot re-enter host tools.
@MainActor
struct ScriptedBatchTool: AgentTool {
    let executionRouter: ExecutionRouter?

    let name = "run_tool_script"
    let description = """
        Run a script that batches multiple steps in one sandboxed pass (collapses a multi-step \
        pipeline). Runs ONLY inside a sandbox with the profile's tool allow-list and resource \
        limits; unavailable if no sandbox backend is configured.
        """
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "script": .object([
                    "type": .string("string"),
                    "description": .string("The script to run inside the sandbox."),
                ]),
                "working_dir": .object([
                    "type": .string("string"),
                    "description": .string("Absolute working directory inside the sandbox."),
                ]),
            ]),
            "required": .array([.string("script")]),
        ])
    }

    func isIrreversible(_ input: JSONValue) -> Bool { true }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let script = input["script"]?.stringValue, !script.isEmpty else {
            throw ToolError.message("run_tool_script requires a non-empty \"script\".")
        }
        guard let router = executionRouter else {
            return ToolResult(
                content: "Scripted batching is unavailable: no sandbox backend (requires Slice 6).",
                isError: true)
        }
        let workingDir = input["working_dir"]?.stringValue
        do {
            // Subagent trust tier → sandboxed backend + profile. No per-Agent
            // policy is threaded through here yet, so this always resolves to
            // the tier's restrictive default (never escalates, never host).
            let (backend, profile) = try await router.route(tier: .subagent, policy: nil)
            let result = try await backend.run(
                ExecutionRequest(
                    command: script, workingDir: workingDir, profile: profile))
            return ToolResult(content: result.output, isError: result.isError)
        } catch let ExecutionRouterError.backendUnavailable(_, message) {
            return ToolResult(content: "Sandbox unavailable: \(message)", isError: true)
        } catch ExecutionRouterError.cloudNotOptedIn {
            return ToolResult(
                content: "Sandbox unavailable: cloud execution requires an explicit opt-in.",
                isError: true)
        } catch {
            return ToolResult(content: "Scripted batch failed: \(error.localizedDescription)", isError: true)
        }
    }
}
