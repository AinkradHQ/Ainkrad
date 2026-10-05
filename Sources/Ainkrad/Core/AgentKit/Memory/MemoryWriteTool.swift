import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Memory/MemoryWriteTool.swift
import Foundation

struct MemoryWriteTool: AgentTool {
    let service: MemoryService

    let name = "memory_write"
    let description = """
        Persist a durable fact, preference, or convention to the assistant's long-term memory. \
        Use this proactively whenever you learn something worth remembering across sessions — \
        no need to ask the user. target: "user" (about the user), "memory" (facts/decisions), \
        or "agents" (rules/conventions to always follow).
        """
    let permission: ToolPermissionClass = .memory

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "target": .object([
                    "type": .string("string"),
                    "enum": .array([.string("user"), .string("memory"), .string("agents")]),
                    "description": .string("Which memory file to append to."),
                ]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("The concise fact to remember (one idea per call)."),
                ]),
            ]),
            "required": .array([.string("target"), .string("content")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let target = input["target"]?.stringValue,
            let file = Self.file(for: target)
        else {
            throw ToolError.message("memory_write requires target = user | memory | agents.")
        }
        guard let content = input["content"]?.stringValue, !content.isEmpty else {
            throw ToolError.message("memory_write requires non-empty \"content\".")
        }
        service.write(content, to: file, provenance: .agent)
        return ToolResult(content: "Remembered in \(file.rawValue).", isError: false)
    }

    private static func file(for target: String) -> MemoryFile? {
        switch target {
        case "user": return .user
        case "memory": return .memory
        case "agents": return .agents
        default: return nil
        }
    }
}
