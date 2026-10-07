import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Skill suggestion chip + badge")
@MainActor
struct SkillSuggestionChipTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chip-\(UUID().uuidString)")
    }

    @Test func acceptClearsThePendingSuggestion() {
        let session = TestSessionFactory.make()
        session.updateSkillSuggestion(
            from: [
                AgentMessage(role: .user, text: "ship"),
                AgentMessage(
                    role: .assistant,
                    content: [
                        .toolUse(id: "0", name: "edit_file", input: .null),
                        .toolUse(id: "1", name: "run_terminal", input: .null),
                        .toolUse(id: "2", name: "git_op", input: .null),
                    ]),
                AgentMessage(
                    role: .user,
                    content: [
                        .toolResult(toolUseID: "0", content: "ok", isError: false),
                        .toolResult(toolUseID: "1", content: "ok", isError: false),
                        .toolResult(toolUseID: "2", content: "ok", isError: false),
                    ]),
                AgentMessage(role: .assistant, text: "done"),
            ], succeeded: true)
        session.acceptSkillSuggestion()
        #expect(session.pendingSkillSuggestion == nil)  // accepted -> cleared, directive sent
    }

    @Test func proposalCountReflectsPendingDrafts() throws {
        let root = temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        try reg.propose(name: "one", description: "d", body: "b")
        let store = SkillCommandStore(persistence: InMemoryPersistenceStore())
        let vm = SkillsManagerViewModel(registry: reg, store: store, resyncCommands: {})
        #expect(vm.proposalCount == 1)
    }
}
