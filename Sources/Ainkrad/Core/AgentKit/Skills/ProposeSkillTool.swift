import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Skills/ProposeSkillTool.swift
import Foundation

/// Lets the agent DRAFT a reusable skill after a gnarly task. The draft lands in
/// `_proposed/` (`SkillRegistry.propose`) and never influences behaviour until
/// the user approves it in the Skills manager (approval-gated because skills
/// change future behaviour) — this tool never touches the active set.
struct ProposeSkillTool: AgentTool {
    let registry: SkillRegistry

    let name = "propose_skill"
    let description = """
        Propose a new reusable skill capturing a procedure you just performed successfully, so it can \
        be reused later. The proposal is saved for the user to review and approve — it does NOT take \
        effect until they approve it. Use a lowercase-hyphenated name. To improve an existing skill, \
        pass its name as both "name" and "improves" with the revised body.
        """
    // PROVISIONAL: retag to .memory if Slice 1's exempt case lands (proposals are inert, so a
    // silent draft would be safe) — until then `.write` keeps it gated in Ask mode.
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Lowercase-hyphenated skill name, e.g. \"release-flow\"."),
                ]),
                "description": .object([
                    "type": .string("string"),
                    "description": .string("One-line summary of what the skill does."),
                ]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string("Markdown step-by-step instructions."),
                ]),
                "improves": .object([
                    "type": .string("string"),
                    "description": .string(
                        "OPTIONAL: the name of an existing skill this revises. When set it must equal \"name\"."),
                ]),
            ]),
            "required": .array([.string("name"), .string("description"), .string("body")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        // Read every field defensively — a missing/empty/wrong-typed field from
        // the model is a clear tool error, never a crash.
        guard let skillName = input["name"]?.stringValue, !skillName.isEmpty else {
            throw ToolError.message("propose_skill requires a non-empty \"name\".")
        }
        guard let description = input["description"]?.stringValue, !description.isEmpty else {
            throw ToolError.message("propose_skill requires a non-empty \"description\".")
        }
        guard let body = input["body"]?.stringValue, !body.isEmpty else {
            throw ToolError.message("propose_skill requires a non-empty \"body\".")
        }
        if let improves = input["improves"]?.stringValue, !improves.isEmpty {
            guard improves == skillName else {
                return ToolResult(
                    content: "\"improves\" must equal \"name\" — an improvement revises that same skill.", isError: true
                )
            }
            guard registry.skill(named: improves) != nil else {
                return ToolResult(
                    content: "Can't improve \"\(improves)\": no active skill by that name.", isError: true)
            }
        }
        do {
            try registry.propose(name: skillName, description: description, body: body)
            return ToolResult(
                content: "Proposed skill \"\(skillName)\" for your review. It will not take effect until approved.",
                isError: false)
        } catch {
            // Covers SkillProposalError.invalid (unsafe name / empty fields caught late) and
            // SkillRegistryError.unsafeName from the underlying propose(_:name:) — either way
            // this is reported back as a tool error, never a crash, and nothing is written.
            return ToolResult(content: "Could not propose skill \"\(skillName)\": \(error)", isError: true)
        }
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let skillName = input["name"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Propose skill", summary: skillName, diff: nil)
    }
}
