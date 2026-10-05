// Tests/AinkradTests/ReadFileToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("ReadFileTool")
@MainActor
struct ReadFileToolTests {
    private func tempFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("readtool-\(UUID().uuidString).txt")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func readsContents() async throws {
        let url = try tempFile("line1\nline2")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try await ReadFileTool().execute(.object(["path": .string(url.path)]))
        #expect(r.content == "line1\nline2")
        #expect(!r.isError)
    }

    @Test func missingPathThrows() async {
        await #expect(throws: ToolError.self) {
            _ = try await ReadFileTool().execute(.object([:]))
        }
    }

    @Test func notFoundThrows() async {
        await #expect(throws: ToolError.self) {
            _ = try await ReadFileTool().execute(.object(["path": .string("/no/such/file.txt")]))
        }
    }

    @Test func directoryPathThrows() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("readtool-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: ToolError.self) {
            _ = try await ReadFileTool().execute(.object(["path": .string(dir.path)]))
        }
    }

    @Test func overCapThrows() async throws {
        let url = try tempFile(String(repeating: "a", count: 300_000))
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: ToolError.self) {
            _ = try await ReadFileTool().execute(.object(["path": .string(url.path)]))
        }
    }
}
