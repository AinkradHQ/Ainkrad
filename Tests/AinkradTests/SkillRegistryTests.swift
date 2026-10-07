import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillRegistry")
@MainActor
struct SkillRegistryTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sr-\(UUID().uuidString)")
    }

    private func write(_ text: String, name: String, root: URL, proposed: Bool = false) throws {
        let paths = SkillPaths(root: root)
        let url = proposed ? paths.proposedFile(name) : paths.skillFile(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func md(_ name: String, _ desc: String) -> String {
        "---\nname: \(name)\ndescription: \(desc)\n---\ninstructions for \(name)"
    }

    @Test func loadsValidSkills() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(md("alpha", "first"), name: "alpha", root: root)
        try write(md("beta", "second"), name: "beta", root: root)
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        #expect(reg.skills.count == 2)
        #expect(reg.skill(named: "alpha")?.description == "first")
    }

    @Test func skipsMalformedAndRecordsError() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("no front matter here", name: "broken", root: root)
        try write(md("good", "ok"), name: "good", root: root)
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        #expect(reg.skills.map(\.name) == ["good"])
        #expect(reg.loadErrors.contains { $0.name == "broken" })
    }

    @Test func skipsNonUTF8FileWithoutCrashing() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        let url = paths.skillFile("badbytes")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        // 0xFF 0xFE is not valid UTF-8.
        let invalidData = Data([0xFF, 0xFE, 0x00, 0x01])
        try invalidData.write(to: url)
        try write(md("good", "ok"), name: "good", root: root)

        let reg = SkillRegistry(paths: paths)
        #expect(reg.skills.map(\.name) == ["good"])
        #expect(reg.loadErrors.contains { $0.name == "badbytes" })
    }

    @Test func ignoresProposedDirectory() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(md("drafted", "pending"), name: "drafted", root: root, proposed: true)
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        #expect(reg.skills.isEmpty)  // _proposed is never in the active set
    }

    @Test func localOverridesMarketplaceByName() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Two dirs whose SKILL.md declare the SAME `name`; "mp-dir" is a marketplace install.
        try write(md("dup", "from marketplace"), name: "mp-dir", root: root)
        try write(md("dup", "from local"), name: "local-dir", root: root)
        let reg = SkillRegistry(
            paths: SkillPaths(root: root),
            marketplaceNames: { ["mp-dir"] })
        #expect(reg.skill(named: "dup")?.description == "from local")
        #expect(reg.skill(named: "dup")?.source == .local)
    }

    @Test func reloadPicksUpNewFilesAndFiresOnChange() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        #expect(reg.skills.isEmpty)
        var fired = false
        reg.onChange = { fired = true }
        try write(md("late", "added later"), name: "late", root: root)
        reg.reload()
        #expect(reg.skill(named: "late") != nil)
        #expect(fired)
    }

    @Test func worksWhenDirectoriesDoNotExistYet() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FileManager.default.fileExists(atPath: root.path))

        let paths = SkillPaths(root: root)
        let reg = SkillRegistry(paths: paths)  // must not crash / throw

        #expect(reg.skills.isEmpty)
        #expect(reg.loadErrors.isEmpty)
        // The registry ensures the directories exist so later writes/reloads work.
        #expect(FileManager.default.fileExists(atPath: paths.root.path))
        #expect(FileManager.default.fileExists(atPath: paths.proposedRoot.path))
    }

    @Test func proposeWritesDraftButNotActive() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        let reg = SkillRegistry(paths: paths)

        try reg.propose(md("draft", "a proposed skill"), name: "draft")

        #expect(FileManager.default.fileExists(atPath: paths.proposedFile("draft").path))
        #expect(reg.skill(named: "draft") == nil)  // inert until approved
        #expect(reg.skills.isEmpty)

        reg.reload()  // even after a reload, still not active
        #expect(reg.skill(named: "draft") == nil)
    }

    @Test func approveMovesProposalIntoActiveSet() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        let reg = SkillRegistry(paths: paths)

        try reg.propose(md("draft", "a proposed skill"), name: "draft")
        try reg.approve(name: "draft")

        #expect(reg.skill(named: "draft")?.description == "a proposed skill")
        #expect(FileManager.default.fileExists(atPath: paths.skillFile("draft").path))
        // Proposal directory should no longer exist post-approval.
        #expect(!FileManager.default.fileExists(atPath: paths.proposedDir("draft").path))
    }

    @Test func discardRemovesProposalWithoutTouchingActive() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        try write(md("good", "ok"), name: "good", root: root)
        let reg = SkillRegistry(paths: paths)

        try reg.propose(md("draft", "a proposed skill"), name: "draft")
        try reg.discard(name: "draft")

        #expect(!FileManager.default.fileExists(atPath: paths.proposedDir("draft").path))
        #expect(reg.skill(named: "draft") == nil)
        #expect(reg.skill(named: "good") != nil)  // untouched
    }

    // MARK: - Path-traversal rejection (security)

    nonisolated private static let traversalNames = ["../../../../tmp/evil", "a/b", ".."]

    @Test(arguments: traversalNames)
    func proposeRejectsTraversalName(name: String) throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        let reg = SkillRegistry(paths: paths)

        // Sentinel just outside the root, to prove no FS effect escapes it.
        let sentinelDir = root.deletingLastPathComponent().appendingPathComponent("sr-sentinel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sentinelDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sentinelDir) }

        #expect(throws: SkillRegistryError.unsafeName(name)) {
            try reg.propose(md("draft", "a proposed skill"), name: name)
        }
        #expect(FileManager.default.fileExists(atPath: sentinelDir.path))
        #expect(reg.skills.isEmpty)
    }

    @Test(arguments: traversalNames)
    func approveRejectsTraversalName(name: String) throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        let reg = SkillRegistry(paths: paths)

        let sentinelDir = root.deletingLastPathComponent().appendingPathComponent("sr-sentinel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sentinelDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sentinelDir) }

        #expect(throws: SkillRegistryError.unsafeName(name)) {
            try reg.approve(name: name)
        }
        #expect(FileManager.default.fileExists(atPath: sentinelDir.path))
        #expect(reg.skills.isEmpty)
    }

    @Test(arguments: traversalNames)
    func discardRejectsTraversalName(name: String) throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        try write(md("good", "ok"), name: "good", root: root)
        let reg = SkillRegistry(paths: paths)

        // Sentinel dir placed just outside `root`, named so that `root/../<sentinel>`
        // would resolve to it if traversal were not blocked.
        let sentinelDir = root.deletingLastPathComponent().appendingPathComponent("tmp-evil")
        try FileManager.default.createDirectory(at: sentinelDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sentinelDir) }

        #expect(throws: SkillRegistryError.unsafeName(name)) {
            try reg.discard(name: name)
        }
        #expect(FileManager.default.fileExists(atPath: sentinelDir.path))
        #expect(reg.skill(named: "good") != nil)  // untouched
    }
}
