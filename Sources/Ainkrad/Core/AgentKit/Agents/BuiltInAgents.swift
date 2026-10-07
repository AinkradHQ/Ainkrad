// Sources/Ainkrad/Core/AgentKit/Agents/BuiltInAgents.swift
import Foundation

enum BuiltInAgents {
    static let planID = UUID(checkedLiteral: "00000000-0000-0000-0000-0000000000A1")
    static let buildID = UUID(checkedLiteral: "00000000-0000-0000-0000-0000000000A2")

    static let plan = AgentProfile(
        id: planID, name: "Plan",
        instructions: """
            You are in PLAN mode. Investigate, read, and reason — but do not modify \
            files, run commands, or mutate git. When your investigation is complete, \
            call `present_plan` with an ordered plan and STOP; the user approves it \
            before any changes are made.
            """,
        toolPolicy: .restricted(allow: ["present_plan"], deny: [], allowClasses: [.read]),
        permissionPosture: nil,
        routing: AgentRouting(routerEnabled: true),
        builtin: true,
        icon: "list.bullet.clipboard")

    static let build = AgentProfile(
        id: buildID, name: "Build",
        instructions: """
            You are in BUILD mode. Read, edit, run commands, and use git via the \
            provided tools, respecting the approval gate.
            """,
        toolPolicy: .restricted(allow: [], deny: ["present_plan"], allowClasses: [.read, .write, .memory]),
        permissionPosture: nil,
        routing: AgentRouting(routerEnabled: true),
        builtin: true,
        icon: "hammer")

    static let all: [AgentProfile] = [plan, build]
}

private extension UUID {
    /// A UUID from a compile-time-constant literal — the `URL(checkedLiteral:)` pattern. A
    /// malformed literal is a programmer error, so it traps with the literal named.
    init(checkedLiteral literal: StaticString) {
        guard let uuid = UUID(uuidString: "\(literal)") else {
            preconditionFailure("Malformed UUID literal: \(literal)")
        }
        self = uuid
    }
}
