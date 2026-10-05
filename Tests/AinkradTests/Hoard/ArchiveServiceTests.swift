import Foundation
import Testing

@testable import Ainkrad

/// Against the real `ditto` and `tar`: the whole reason to shell out is their
/// macOS-correct behaviour, which a fake could not demonstrate.
@Suite("Archive service", .serialized)
struct ArchiveServiceTests {
    private func makeWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("round-trips a single file through zip and back")
    func roundTripSingleFile() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("payload.txt")
        try "contents".write(to: file, atomically: true, encoding: .utf8)

        let service = SystemArchiveService()
        let archive = try service.archive([file], to: root.appendingPathComponent("out.zip"))
        #expect(FileManager.default.fileExists(atPath: archive.path))

        let destination = root.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let created = try service.extract(archive, into: destination)

        #expect(!created.isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("payload.txt").path))
        #expect(
            try String(
                contentsOf: destination.appendingPathComponent("payload.txt"),
                encoding: .utf8) == "contents")
    }

    @Test("archives a directory, preserving its structure")
    func archivesDirectory() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("src"),
            withIntermediateDirectories: true)
        try "code".write(
            to: folder.appendingPathComponent("src/main.swift"),
            atomically: true, encoding: .utf8)

        let service = SystemArchiveService()
        let archive = try service.archive([folder], to: root.appendingPathComponent("proj.zip"))

        let destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try service.extract(archive, into: destination)

        #expect(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("project/src/main.swift").path))
    }

    @Test("reports which top-level items an extraction created")
    func reportsCreatedItems() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("solo.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let service = SystemArchiveService()
        let archive = try service.archive([file], to: root.appendingPathComponent("solo.zip"))

        let destination = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // Pre-existing content must NOT be reported as created.
        try "old".write(
            to: destination.appendingPathComponent("pre-existing.txt"),
            atomically: true, encoding: .utf8)

        let created = try service.extract(archive, into: destination)
        #expect(!created.contains { $0.lastPathComponent == "pre-existing.txt" })
    }

    @Test("recognises extractable extensions")
    func recognisesExtensions() {
        let service = SystemArchiveService()
        #expect(service.canExtract(URL(fileURLWithPath: "/x/a.zip")))
        #expect(service.canExtract(URL(fileURLWithPath: "/x/a.tar")))
        #expect(service.canExtract(URL(fileURLWithPath: "/x/a.gz")))
        #expect(!service.canExtract(URL(fileURLWithPath: "/x/a.txt")))
        #expect(!service.canExtract(URL(fileURLWithPath: "/x/a.swift")))
    }

    @Test("extracting a non-archive throws rather than producing junk")
    func rejectsNonArchive() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.txt")
        try "plain".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try SystemArchiveService().extract(file, into: root)
        }
    }

    @Test("archiving nothing throws instead of writing an empty archive")
    func rejectsEmptySelection() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) {
            try SystemArchiveService().archive([], to: root.appendingPathComponent("empty.zip"))
        }
    }

    @Test("default names follow the selection, not a generic Archive.zip")
    func defaultNames() {
        let directory = URL(fileURLWithPath: "/Users/test/project")
        #expect(
            defaultArchiveName(
                for: [directory.appendingPathComponent("notes.md")],
                in: directory) == "notes.zip")
        #expect(
            defaultArchiveName(
                for: [
                    directory.appendingPathComponent("a"),
                    directory.appendingPathComponent("b"),
                ],
                in: directory) == "project.zip")
    }
}
