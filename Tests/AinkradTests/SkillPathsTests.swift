import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillPaths")
struct SkillPathsTests {
    @Test func mapsNamesToLayout() {
        let root = URL(fileURLWithPath: "/tmp/skills-\(UUID().uuidString)")
        let p = SkillPaths(root: root)
        #expect(p.proposedRoot.lastPathComponent == "_proposed")
        #expect(p.skillDir("pdf").lastPathComponent == "pdf")
        #expect(p.skillFile("pdf").lastPathComponent == "SKILL.md")
        #expect(p.skillFile("pdf").deletingLastPathComponent().lastPathComponent == "pdf")
        #expect(p.proposedFile("pdf").lastPathComponent == "SKILL.md")
        // _proposed sits UNDER root, not beside it.
        #expect(p.proposedDir("pdf").deletingLastPathComponent().lastPathComponent == "_proposed")
    }

    /// `SkillPaths` must not be able to compute a storage path of its own: the
    /// root always comes from the resolved `Home` (or a test temp dir). The
    /// deleted `defaultRoot()` is what let the suite reach the developer's real
    /// Skills tree, so its absence is the regression guard.
    @Test func rootIsAlwaysCallerSupplied() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)", isDirectory: true)
        #expect(SkillPaths(root: root).root == root)
    }
}
