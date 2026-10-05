// Tests/AinkradTests/EditFileToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("EditFileTool")
@MainActor
struct EditFileToolTests {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("edittool-\(UUID().uuidString).txt").path
    }

    @Test func replacesUniqueMatch() async throws {
        let path = tempPath()
        try "hello world".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let r = try await EditFileTool().execute(
            .object([
                "path": .string(path),
                "old_string": .string("world"),
                "new_string": .string("there"),
            ]))
        #expect(!r.isError)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "hello there")
    }

    @Test func zeroMatchesThrows() async throws {
        let path = tempPath()
        try "abc".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        await #expect(throws: ToolError.self) {
            _ = try await EditFileTool().execute(
                .object([
                    "path": .string(path), "old_string": .string("zzz"), "new_string": .string("q"),
                ]))
        }
    }

    @Test func multipleMatchesThrows() async throws {
        let path = tempPath()
        try "x x".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        await #expect(throws: ToolError.self) {
            _ = try await EditFileTool().execute(
                .object([
                    "path": .string(path), "old_string": .string("x"), "new_string": .string("y"),
                ]))
        }
    }

    @Test func directoryPathThrows() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("edittool-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: ToolError.self) {
            _ = try await EditFileTool().execute(
                .object([
                    "path": .string(dir.path), "old_string": .string("x"), "new_string": .string("y"),
                ]))
        }
    }

    @Test func emptyOldStringCreatesFile() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let r = try await EditFileTool().execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("fresh"),
            ]))
        #expect(!r.isError)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "fresh")
    }

    @Test func previewProducesDiff() async throws {
        let path = tempPath()
        try "hello world".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let preview = EditFileTool().approvalPreview(
            .object([
                "path": .string(path), "old_string": .string("world"), "new_string": .string("there"),
            ]))
        #expect(preview.diff?.contains("-hello world") == true)
        #expect(preview.diff?.contains("+hello there") == true)
    }
}
