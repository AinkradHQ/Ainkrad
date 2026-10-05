import Foundation
import Testing

@testable import Ainkrad

/// Covers `SkillRegistry.proposals()` — the review-list surface Task 8 adds on
/// top of Task 4's propose/approve/discard. `approve`/`discard` themselves are
/// exercised in `SkillRegistryTests`; here we only confirm they interact
/// correctly with the new listing (removed from it, active-set effects).
@Suite("Skill proposal review")
@MainActor
struct SkillProposalTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("prop-\(UUID().uuidString)")
    }

    private func md(_ name: String, _ desc: String, body: String = "steps") -> String {
        "---\nname: \(name)\ndescription: \(desc)\n---\n\(body)"
    }

    @Test func listsProposalWithParsedContentAndNoIssues() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))

        try reg.propose(name: "one", description: "first draft", body: "steps")

        let proposals = reg.proposals()
        #expect(proposals.map(\.name) == ["one"])
        #expect(proposals.first?.skill?.description == "first draft")
        #expect(proposals.first?.skill?.source == .proposed)
        #expect(proposals.first?.issues.isEmpty == true)
        #expect(proposals.first?.error == nil)
    }

    @Test func malformedProposalIsListedWithErrorNotSkipped() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        // Bypass propose()'s validation to simulate a hand-edited/corrupt draft.
        let url = paths.proposedFile("broken")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "no front matter here".write(to: url, atomically: true, encoding: .utf8)

        let reg = SkillRegistry(paths: paths)
        let proposals = reg.proposals()

        #expect(proposals.map(\.name) == ["broken"])
        #expect(proposals.first?.skill == nil)
        #expect(proposals.first?.error != nil)
    }

    @Test func proposalWithValidationIssuesSurfacesThem() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        // Parses fine (name + description present) but body is empty -> validator flags it.
        let url = paths.proposedFile("empty-body")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try md("empty-body", "has no body", body: "").write(to: url, atomically: true, encoding: .utf8)

        let reg = SkillRegistry(paths: paths)
        let proposals = reg.proposals()

        #expect(proposals.first?.skill != nil)
        #expect(proposals.first?.issues.contains(.emptyBody) == true)
        #expect(proposals.first?.error == nil)
    }

    @Test func orderingIsDeterministic() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))

        try reg.propose(name: "zeta", description: "z", body: "steps")
        try reg.propose(name: "alpha", description: "a", body: "steps")
        try reg.propose(name: "mid", description: "m", body: "steps")

        #expect(reg.proposals().map(\.name) == ["alpha", "mid", "zeta"])
    }

    @Test func approveActivatesAndRemovesFromProposals() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))

        try reg.propose(name: "handy", description: "useful", body: "do it")
        #expect(reg.skill(named: "handy") == nil)

        try reg.approve(name: "handy")

        #expect(reg.skill(named: "handy")?.source == .local)
        #expect(reg.proposals().isEmpty)
    }

    @Test func discardRemovesFromProposalsWithoutActivating() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))

        try reg.propose(name: "nope", description: "unwanted", body: "steps")
        try reg.discard(name: "nope")

        #expect(reg.proposals().isEmpty)
        #expect(reg.skill(named: "nope") == nil)
    }

    @Test func emptyWhenNoProposalsExist() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        #expect(reg.proposals().isEmpty)
    }
}
