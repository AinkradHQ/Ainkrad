import AinkradHostRuntime
import Foundation

/// The Plan persona's turn-ending tool. It emits a structured plan for the user
/// to approve; it touches NO files or system state, so it is `.memory`-class —
/// the one class `AgentPermissionPolicy.decide` auto-approves unconditionally
/// (see `AgentPermissionModel` `toolPermission == .memory` exemption), so it
/// never hits the approval gate even when reads are gated. The plan itself is
/// reconstructed from the transcript by `TranscriptTimelineBuilder`; this tool
/// only validates the payload and returns a result that instructs the model to
/// STOP, which ends the planning turn (the model produces a plain end_turn on
/// the next round rather than calling more tools). Available to the Plan
/// persona only — added to `BuiltInAgents.plan`'s allow-list and denied on
/// `BuiltInAgents.build` (Task 3).
struct PresentPlanTool: AgentTool {
    let name = "present_plan"
    let description = """
        Present a structured, ordered plan for the user to approve before any files \
        are changed. Call this ONCE when your investigation is complete, with the \
        FULL plan: a short `summary` and an ordered `steps` array (each step an \
        object with a `title`). This tool changes nothing — after calling it, STOP \
        and wait for the user to Approve & Build or ask for changes.
        """
    let permission: ToolPermissionClass = .memory

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "summary": .object([
                    "type": .string("string"),
                    "description": .string("One or two sentences on the overall approach."),
                ]),
                "steps": .object([
                    "type": .string("array"),
                    "description": .string("The complete ordered list of steps to implement."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("Short imperative step description."),
                            ])
                        ]),
                        "required": .array([.string("title")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("steps")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let plan = PlanArtifact.from(input) else {
            return ToolResult(
                content: "present_plan requires a non-empty \"steps\" array (each step an object with a \"title\").",
                isError: true)
        }
        var lines: [String] = []
        if !plan.summary.isEmpty { lines.append(plan.summary) }
        for (index, step) in plan.steps.enumerated() { lines.append("\(index + 1). \(step.title)") }
        let body = lines.joined(separator: "\n")
        return ToolResult(
            content: "Plan presented to the user for approval. Do NOT take further action or call more "
                + "tools — stop and wait for the user to Approve & Build or ask for changes.\n\n" + body,
            isError: false)
    }
}
