import AinkradHostRuntime
import Foundation

/// Maintains the agent's per-session task checklist. It mutates only display
/// state (the transcript renders the LATEST call as a live checklist node), never
/// the workspace, so it is `.memory`-class — auto-approved in every permission
/// mode (see `AgentPermissionModel` `toolPermission == .memory` exemption). The
/// list itself is reconstructed from the transcript by `TranscriptTimelineBuilder`;
/// this tool only validates the payload and echoes the current list back to the
/// model so it can reason about progress on the next turn.
struct TodoWriteTool: AgentTool {
    let name = "todo_write"
    let description = """
        Maintain a task checklist for the current session. Call with the FULL list \
        every time (it replaces the previous list in place). Each item has `content` \
        and `status` (one of: pending, in_progress, completed). Use this to plan and \
        track multi-step work; it does not touch the workspace.
        """
    let permission: ToolPermissionClass = .memory

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "items": .object([
                    "type": .string("array"),
                    "description": .string("The complete, ordered task list (replaces the prior list)."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Short imperative task description."),
                            ]),
                            "status": .object([
                                "type": .string("string"),
                                "enum": .array([.string("pending"), .string("in_progress"), .string("completed")]),
                                "description": .string("Task status."),
                            ]),
                        ]),
                        "required": .array([.string("content"), .string("status")]),
                    ]),
                ])
            ]),
            "required": .array([.string("items")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        let items = TodoItem.list(from: input)
        guard !items.isEmpty else {
            return ToolResult(content: "todo_write requires a non-empty \"items\" array.", isError: true)
        }
        let lines = items.map { item -> String in
            let box: String
            switch item.status {
            case .pending: box = "[ ]"
            case .inProgress: box = "[~]"
            case .completed: box = "[x]"
            }
            return "\(box) \(item.content)"
        }
        return ToolResult(content: "Task list updated:\n" + lines.joined(separator: "\n"), isError: false)
    }
}
