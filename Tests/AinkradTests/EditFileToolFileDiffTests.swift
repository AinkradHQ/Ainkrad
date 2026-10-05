import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("EditFileToolFileDiff")
@MainActor
struct EditFileToolFileDiffTests {
    @Test func previewCarriesStructuredFileDiff() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("f.txt").path
        try (1...10).map { "line \($0)" }.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)

        let preview = EditFileTool().approvalPreview(
            .object([
                "path": .string(path),
                "old_string": .string("line 3"),
                "new_string": .string("line 3 EDITED"),
            ]))
        let fileDiff = try #require(preview.fileDiff)
        #expect(fileDiff.hunks.count == 1)
        #expect(fileDiff.original.contains("line 3"))
        #expect(preview.diff != nil)  // string diff still present for back-compat
    }
}
