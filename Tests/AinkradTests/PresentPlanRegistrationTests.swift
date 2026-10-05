import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("PresentPlanRegistration")
@MainActor
struct PresentPlanRegistrationTests {
    @Test func registryExposesPresentPlan() {
        // Mirrors the base tool set assembled in bootstrapExecutionAndTools.
        let registry = AgentToolRegistry(tools: [FakeReadFileTool(), PresentPlanTool()])
        #expect(registry.tool(named: "present_plan") != nil)
        #expect(registry.schemas.contains { $0.name == "present_plan" })
    }

    @Test func planPersonaAllowsPresentPlanButNotEdits() {
        let plan = BuiltInAgents.plan.toolPolicy
        #expect(plan.allows(toolName: "present_plan", permission: .memory))
        #expect(plan.allows(toolName: "read_file", permission: .read))
        #expect(!plan.allows(toolName: "edit_file", permission: .write))  // still read-only for edits
    }

    @Test func buildPersonaDeniesPresentPlanButKeepsEverythingElse() {
        let build = BuiltInAgents.build.toolPolicy
        #expect(!build.allows(toolName: "present_plan", permission: .memory))  // Plan-only
        #expect(build.allows(toolName: "edit_file", permission: .write))
        #expect(build.allows(toolName: "read_file", permission: .read))
        #expect(build.allows(toolName: "memory_write", permission: .memory))
    }
}
