import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Skill improvement")
@MainActor
struct SkillImprovementTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("imp-\(UUID().uuidString)")
    }

    @Test func proposalOfExistingNameIsFlaggedAsRevision() throws {
        let root = temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        try reg.writeLocal("---\nname: deploy\ndescription: old\n---\nold steps", name: "deploy")
        try reg.propose(name: "deploy", description: "better", body: "new steps")
        let p = reg.proposals().first { $0.name == "deploy" }
        #expect(p?.isRevision == true)
    }

    @Test func brandNewProposalIsNotARevision() throws {
        let root = temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        try reg.propose(name: "fresh", description: "d", body: "b")
        #expect(reg.proposals().first?.isRevision == false)
    }

    @Test func improvesMustMatchAnExistingSkill() async throws {
        let root = temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        let tool = ProposeSkillTool(registry: reg)
        let result = try await tool.execute(
            .object([
                "name": .string("deploy"), "description": .string("d"),
                "body": .string("b"), "improves": .string("nonexistent"),
            ]))
        #expect(result.isError == true)
        #expect(reg.proposals().isEmpty)
    }

    @Test func improvesDraftsRevisionWhenSkillExists() async throws {
        let root = temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        try reg.writeLocal("---\nname: deploy\ndescription: old\n---\nold", name: "deploy")
        let tool = ProposeSkillTool(registry: reg)
        let result = try await tool.execute(
            .object([
                "name": .string("deploy"), "description": .string("better"),
                "body": .string("new steps"), "improves": .string("deploy"),
            ]))
        #expect(result.isError == false)
        #expect(reg.proposals().first { $0.name == "deploy" }?.isRevision == true)
    }
}
