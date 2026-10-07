import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Skills/UseSkillTool.swift
import Foundation

/// Loads one skill's full instructions on demand (progressive disclosure). The
/// model discovers skill names via the index context source (Task 5), then
/// calls this to read the body before following it. This tool only RETURNS
/// text — any tool the skill's instructions go on to drive runs through the
/// normal permission gate, same as if the model had typed those steps itself.
struct UseSkillTool: AgentTool {
    let registry: SkillRegistry

    let name = "use_skill"
    let description = """
        Load the full step-by-step instructions for a named skill from the "Available Skills" index. \
        Call this before performing a workflow a skill covers, then follow the returned instructions. \
        Only pass a name that appears verbatim in that index, and only when the request clearly \
        matches it — not for greetings, small talk, or when no skill is listed.
        """
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("The skill name from the Available Skills index."),
                ])
            ]),
            "required": .array([.string("name")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let skillName = input["name"]?.stringValue, !skillName.isEmpty else {
            throw ToolError.message("use_skill requires a non-empty \"name\".")
        }
        // Only the active set (installed/local) is usable — a proposed, not-yet-
        // approved draft must never be loaded this way.
        guard let skill = registry.skill(named: skillName) else {
            return ToolResult(content: "No skill named \"\(skillName)\".", isError: true)
        }
        var header = "# Skill: \(skill.name)\n\(skill.description)"
        if !skill.allowedTools.isEmpty {
            header += "\nAllowed tools: \(skill.allowedTools.joined(separator: ", "))"
        }
        return ToolResult(content: "\(header)\n\n\(skill.body)", isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let skillName = input["name"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Use skill", summary: skillName, diff: nil)
    }
}
