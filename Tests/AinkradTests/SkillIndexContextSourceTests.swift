import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillIndexContextSource")
@MainActor
struct SkillIndexContextSourceTests {
    private func registry(_ names: [(String, String)]) throws -> (SkillRegistry, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sic-\(UUID().uuidString)")
        for (n, d) in names {
            let url = SkillPaths(root: root).skillFile(n)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try "---\nname: \(n)\ndescription: \(d)\n---\nbody".write(to: url, atomically: true, encoding: .utf8)
        }
        return (SkillRegistry(paths: SkillPaths(root: root)), root)
    }

    @Test func nilWhenNoSkills() throws {
        let (reg, root) = try registry([])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SkillIndexContextSource.snapshot(from: reg) == nil)
    }

    @Test func listsNameAndDescription() throws {
        let (reg, root) = try registry([("pdf", "work with PDFs"), ("git", "git workflows")])
        defer { try? FileManager.default.removeItem(at: root) }
        let snap = SkillIndexContextSource.snapshot(from: reg)
        #expect(snap?.kind == "skills-index")
        #expect(snap?.text.contains("pdf: work with PDFs") == true)
        #expect(snap?.text.contains("git: git workflows") == true)
        #expect(snap?.text.contains("use_skill") == true)  // tells the model how to load a body
        // Guardrail against over-triggering: the index must warn the model off
        // inventing names / firing on trivial turns (see fix/skill-overtriggering).
        #expect(snap?.text.contains("never invent") == true)
    }

    @Test func reflectsCurrentActiveSetAfterReload() throws {
        let (reg, root) = try registry([("pdf", "work with PDFs")])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = SkillPaths(root: root).skillFile("git")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "---\nname: git\ndescription: git workflows\n---\nbody".write(to: url, atomically: true, encoding: .utf8)
        reg.reload()
        let snap = SkillIndexContextSource.snapshot(from: reg)
        #expect(snap?.text.contains("pdf: work with PDFs") == true)
        #expect(snap?.text.contains("git: git workflows") == true)
    }

    @Test func deterministicOrdering() throws {
        let (reg, root) = try registry([("zzz", "last"), ("aaa", "first")])
        defer { try? FileManager.default.removeItem(at: root) }
        let snap = SkillIndexContextSource.snapshot(from: reg)
        let text = try #require(snap?.text)
        let aaaIndex = try #require(text.range(of: "aaa: first"))
        let zzzIndex = try #require(text.range(of: "zzz: last"))
        #expect(aaaIndex.lowerBound < zzzIndex.lowerBound)
    }
}
