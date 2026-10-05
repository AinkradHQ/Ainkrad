import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Autonomy/SpawnSubagentTool.swift
import Foundation

/// `AgentTool` that delegates one or more scoped sub-tasks to parallel child
/// agents via `SubagentCoordinator`. Parses the LLM-supplied JSON input
/// defensively (it is untrusted): malformed shapes surface as a `ToolError`,
/// never a crash.
@MainActor
struct SpawnSubagentTool: AgentTool {
    let coordinator: SubagentCoordinator
    let agents: AgentStore

    /// Bounds a single call's fan-out so a runaway prompt (e.g. "spawn 1000
    /// subagents") can't exhaust concurrency/resources. Chosen well above the
    /// coordinator's default `maxConcurrent` (4) — batches beyond that just
    /// queue — but still small enough to reject clearly pathological input.
    static let maxTasksPerCall = 16

    let name = "spawn_subagent"
    let description = """
        Delegate one or more scoped sub-tasks to parallel child agents. Each task runs in its own \
        isolated context with its own tool allow-list; risky tools stay behind the permission gate. \
        Prefer this for independent work you can fan out (audit N modules, draft M files). Provide \
        `tasks` (array) or a single `prompt`. `model_budget` picks the model class (local|free|\
        cheapPaid|premium); the router assigns the concrete model so a fleet stays cheap. At most \
        \(maxTasksPerCall) tasks per call.
        """
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string("Single-task shorthand for a one-element tasks array."),
                ]),
                "tasks": .object([
                    "type": .string("array"),
                    "description": .string("The sub-tasks to run in parallel (max \(Self.maxTasksPerCall))."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "prompt": .object(["type": .string("string")]),
                            "agent": .object([
                                "type": .string("string"),
                                "description": .string("Name of an Agent persona to use."),
                            ]),
                            "tools": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")]),
                            ]),
                            "model_budget": .object([
                                "type": .string("string"),
                                "enum": .array([
                                    .string("local"), .string("free"),
                                    .string("cheapPaid"), .string("premium"),
                                ]),
                            ]),
                        ]),
                        "required": .array([.string("prompt")]),
                    ]),
                ]),
            ]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        let specs = try makeSpecs(from: input)
        guard !specs.isEmpty else {
            throw ToolError.message(
                "spawn_subagent requires at least one task (\"tasks\" array or a top-level \"prompt\").")
        }
        guard specs.count <= Self.maxTasksPerCall else {
            throw ToolError.message(
                "spawn_subagent requested \(specs.count) tasks, which exceeds the max of \(Self.maxTasksPerCall) per call."
            )
        }
        let outcomes = await coordinator.spawn(specs)
        let allFailed = !outcomes.isEmpty && outcomes.allSatisfy { $0.status == .failed }
        let body = outcomes.enumerated().map { i, o in
            "### Subagent \(i + 1) (\(o.status.rawValue))\n\(o.resultText)"
        }.joined(separator: "\n\n")
        return ToolResult(content: body.isEmpty ? "No subagents ran." : body, isError: allFailed)
    }

    // MARK: - Parsing

    private func makeSpecs(from input: JSONValue) throws -> [SubagentSpec] {
        let rawTasks = input["tasks"]

        // "tasks" present but not an array is a malformed shape, not "absent" —
        // fail loudly rather than silently falling back to the prompt shorthand.
        if let rawTasks {
            guard case .array(let items) = rawTasks else {
                throw ToolError.message("spawn_subagent \"tasks\" must be an array.")
            }
            return try items.map(specFrom)
        }

        if let prompt = input["prompt"]?.stringValue, !prompt.isEmpty {
            return [try specFrom(.object(["prompt": .string(prompt)]))]
        }

        return []
    }

    private func specFrom(_ item: JSONValue) throws -> SubagentSpec {
        guard let prompt = item["prompt"]?.stringValue, !prompt.isEmpty else {
            throw ToolError.message("Each spawn_subagent task requires a non-empty \"prompt\".")
        }
        let profileID = item["agent"]?.stringValue.flatMap { name in
            agents.agents.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
        }
        var allow: [String] = []
        if case .array(let toolArr)? = item["tools"] {
            allow = toolArr.compactMap { $0.stringValue }
        }
        let budget = Self.tier(item["model_budget"]?.stringValue)
        return SubagentSpec(prompt: prompt, profileID: profileID, toolAllowList: allow, budgetTier: budget)
    }

    private static func tier(_ raw: String?) -> ModelTier {
        switch raw {
        case "local": return .local
        case "free": return .free
        case "premium": return .premium
        default: return .cheapPaid
        }
    }
}
