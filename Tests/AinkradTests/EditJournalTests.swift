// Tests/AinkradTests/EditJournalTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("EditJournal")
@MainActor
struct EditJournalTests {
    private func tmpFile(_ contents: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ej-\(UUID().uuidString).txt")
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test func revertRestoresPriorContents() {
        let path = tmpFile("original")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let j = EditJournal()
        try? "changed".write(toFile: path, atomically: true, encoding: .utf8)
        let id = j.record(path: path, before: "original", after: "changed", existedBefore: true)
        #expect(j.revert(id))
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "original")
        #expect(j.entries.isEmpty)
    }

    @Test func revertDeletesFileThatDidNotExist() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ej-new-\(UUID().uuidString).txt").path
        try? "created".write(toFile: path, atomically: true, encoding: .utf8)
        let j = EditJournal()
        let id = j.record(path: path, before: "", after: "created", existedBefore: false)
        #expect(j.revert(id))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func revertEntriesAfterIndexUndoesTurn() {
        let p1 = tmpFile("a")
        let p2 = tmpFile("b")
        defer {
            try? FileManager.default.removeItem(atPath: p1)
            try? FileManager.default.removeItem(atPath: p2)
        }
        let j = EditJournal()
        j.record(path: p1, before: "a", after: "a2", existedBefore: true)  // pre-turn (index 0)
        let mark = j.count
        try? "b2".write(toFile: p2, atomically: true, encoding: .utf8)
        j.record(path: p2, before: "b", after: "b2", existedBefore: true)  // turn edit (index 1)
        #expect(j.revertEntries(after: mark) == 1)
        #expect((try? String(contentsOfFile: p2, encoding: .utf8)) == "b")
        #expect(j.count == 1)  // pre-turn entry kept
    }

    @Test func revertMultipleEditsToSameFileInReverseOrder() {
        let path = tmpFile("v0")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let j = EditJournal()
        let mark = j.count
        j.record(path: path, before: "v0", after: "v1", existedBefore: true)
        j.record(path: path, before: "v1", after: "v2", existedBefore: true)
        try? "v2".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(j.revertEntries(after: mark) == 2)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v0")
        #expect(j.count == 0)
    }

    @Test func revertGracefullyHandlesMissingFile() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ej-missing-\(UUID().uuidString).txt")
            .path
        let j = EditJournal()
        // File was removed externally after the edit; revert should not crash.
        let id = j.record(path: path, before: "orig", after: "changed", existedBefore: true)
        _ = j.revert(id)
        #expect(
            !FileManager.default.fileExists(atPath: path)
                || (try? String(contentsOfFile: path, encoding: .utf8)) == "orig")
    }

    @Test func editFileToolRecordsIntoJournal() async throws {
        let path = tmpFile("hello world")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let j = EditJournal()
        let tool = EditFileTool(journal: j)
        _ = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string("world"), "new_string": .string("there"),
            ]))
        #expect(j.entries.count == 1)
        #expect(j.entries.first?.before == "hello world")
        #expect(j.entries.first?.after == "hello there")
    }

    @Test func editFileToolWithNilJournalBehavesIdentically() async throws {
        let path = tmpFile("hello world")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tool = EditFileTool()
        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string("world"), "new_string": .string("there"),
            ]))
        #expect(!r.isError)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "hello there")
    }

    @Test func createdFileRecordsExistedBeforeFalse() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ej-create-\(UUID().uuidString).txt")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let j = EditJournal()
        let tool = EditFileTool(journal: j)
        _ = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("brand new"),
            ]))
        #expect(j.entries.count == 1)
        #expect(j.entries.first?.existedBefore == false)
        #expect(j.revertEntries(after: 0) == 1)
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
