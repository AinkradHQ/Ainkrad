// Tests/AinkradTests/UseSkillToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("UseSkillTool")
@MainActor
struct UseSkillToolTests {
    private func make(_ entries: [(name: String, markdown: String)]) throws -> (UseSkillTool, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("us-\(UUID().uuidString)")
        for entry in entries {
            let url = SkillPaths(root: root).skillFile(entry.name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try entry.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
        return (UseSkillTool(registry: SkillRegistry(paths: SkillPaths(root: root))), root)
    }

    @Test func returnsFullBodyForKnownSkill() async throws {
        let md = "---\nname: deploy\ndescription: ship it\nallowed-tools: run_terminal\n---\nStep 1: run make release"
        let (tool, root) = try make([(name: "deploy", markdown: md)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(tool.permission == .read)
        let r = try await tool.execute(.object(["name": .string("deploy")]))
        #expect(!r.isError)
        #expect(r.content.contains("Step 1: run make release"))
        #expect(r.content.contains("run_terminal"))  // allowed-tools surfaced
    }

    @Test func errorsForUnknownSkill() async throws {
        let md = "---\nname: known\ndescription: d\n---\nbody"
        let (tool, root) = try make([(name: "known", markdown: md)])
        defer { try? FileManager.default.removeItem(at: root) }
        let r = try await tool.execute(.object(["name": .string("missing")]))
        #expect(r.isError)
        #expect(r.content.contains("missing"))
    }

    @Test func throwsWhenNameMissing() async throws {
        let md = "---\nname: known\ndescription: d\n---\nbody"
        let (tool, root) = try make([(name: "known", markdown: md)])
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object([:]))
        }
    }

    @Test func throwsWhenNameEmpty() async throws {
        let md = "---\nname: known\ndescription: d\n---\nbody"
        let (tool, root) = try make([(name: "known", markdown: md)])
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object(["name": .string("")]))
        }
    }

    @Test func throwsWhenNameWrongType() async throws {
        let md = "---\nname: known\ndescription: d\n---\nbody"
        let (tool, root) = try make([(name: "known", markdown: md)])
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object(["name": .number(1)]))
        }
    }

    /// A proposed-but-not-approved skill must NOT be loadable — only the
    /// active set (installed/local) is usable by `use_skill`.
    @Test func proposedNotActiveSkillIsNotFound() async throws {
        let md = "---\nname: known\ndescription: d\n---\nbody"
        let (tool, root) = try make([(name: "known", markdown: md)])
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillPaths(root: root)
        try paths.ensureDirectoriesExist()
        let proposedText = "---\nname: draft\ndescription: pending\n---\nsecret body"
        try FileManager.default.createDirectory(
            at: paths.proposedFile("draft").deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try proposedText.write(to: paths.proposedFile("draft"), atomically: true, encoding: .utf8)

        let r = try await tool.execute(.object(["name": .string("draft")]))
        #expect(r.isError)
        #expect(!r.content.contains("secret body"))
    }
}
