// Tests/AinkradTests/ProposeSkillToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("ProposeSkillTool")
@MainActor
struct ProposeSkillToolTests {
    private func make() -> (ProposeSkillTool, SkillRegistry, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)")
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        return (ProposeSkillTool(registry: reg), reg, root)
    }

    @Test func writesProposalToProposedDirNotActiveSet() async throws {
        let (tool, reg, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(tool.permission == .write)
        let r = try await tool.execute(
            .object([
                "name": .string("release-flow"),
                "description": .string("how to cut a release"),
                "body": .string("1. bump version\n2. make release"),
            ]))
        #expect(!r.isError)
        let file = SkillPaths(root: root).proposedFile("release-flow")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(reg.skill(named: "release-flow") == nil)  // inert until approved
    }

    @Test func rejectsUnsafeName() async throws {
        let (tool, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        let r = try await tool.execute(
            .object([
                "name": .string("../escape"),
                "description": .string("d"),
                "body": .string("b"),
            ]))
        #expect(r.isError)
        // Nothing landed anywhere under root — not in _proposed, not escaped above it.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let proposedContents =
            (try? FileManager.default.contentsOfDirectory(
                atPath: SkillPaths(root: root).proposedRoot.path)) ?? []
        #expect(!contents.contains("escape"))
        #expect(proposedContents.isEmpty)
        // The traversal target itself must not exist beside the temp root.
        let escapedPath = root.deletingLastPathComponent().appendingPathComponent("escape")
        #expect(!FileManager.default.fileExists(atPath: escapedPath.path))
    }

    @Test func throwsWhenNameMissing() async throws {
        let (tool, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(
                .object([
                    "description": .string("d"),
                    "body": .string("b"),
                ]))
        }
    }

    @Test func throwsWhenNameEmpty() async throws {
        let (tool, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(
                .object([
                    "name": .string(""),
                    "description": .string("d"),
                    "body": .string("b"),
                ]))
        }
    }

    @Test func throwsWhenNameWrongType() async throws {
        let (tool, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(
                .object([
                    "name": .number(1),
                    "description": .string("d"),
                    "body": .string("b"),
                ]))
        }
    }

    @Test func throwsWhenDescriptionMissing() async throws {
        let (tool, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(
                .object([
                    "name": .string("release-flow"),
                    "body": .string("b"),
                ]))
        }
    }

    @Test func throwsWhenBodyEmpty() async throws {
        let (tool, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(
                .object([
                    "name": .string("release-flow"),
                    "description": .string("d"),
                    "body": .string(""),
                ]))
        }
    }
}
