import Foundation
import Testing
@testable import Ainkrad

@Suite("CrashLogWriter")
struct CrashLogWriterTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashLogWriterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func report(_ summary: String) -> CrashReport {
        CrashReport(kind: .uncaughtException, timestamp: Date(timeIntervalSince1970: 0),
                    appVersion: "1.0", summary: summary, detail: "d", stack: [])
    }

    @Test func appendCreatesTheFileAndStoresOneRecord() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let writer = CrashLogWriter(directory: dir)
        writer.append(report("first"))
        #expect(writer.readAll().map(\.summary) == ["first"])
    }

    @Test func appendsAccumulateInOrder() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let writer = CrashLogWriter(directory: dir)
        writer.append(report("a")); writer.append(report("b")); writer.append(report("c"))
        #expect(writer.readAll().map(\.summary) == ["a", "b", "c"])
    }

    @Test func aSecondWriterSeesRecordsWrittenByTheFirst() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        CrashLogWriter(directory: dir).append(report("persisted"))
        #expect(CrashLogWriter(directory: dir).readAll().map(\.summary) == ["persisted"])
    }

    @Test func rotatesOnceTheCapIsExceededSoTheLogCannotGrowForever() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        // A cap far below one record forces rotation on the second append.
        let writer = CrashLogWriter(directory: dir, maxBytes: 64)
        writer.append(report("old"))
        writer.append(report("new"))
        let summaries = writer.readAll().map(\.summary)
        #expect(summaries == ["new"])
        #expect(FileManager.default.fileExists(atPath: writer.fileURL.appendingPathExtension("1").path))
    }

    @Test func aCorruptTrailingLineDoesNotLoseTheGoodRecordsBeforeIt() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let writer = CrashLogWriter(directory: dir)
        writer.append(report("good"))
        // Simulate a crash mid-write: a truncated final line.
        let handle = try FileHandle(forWritingTo: writer.fileURL)
        handle.seekToEndOfFile()
        handle.write(Data(#"{"kind":"unc"#.utf8))
        try handle.close()
        #expect(writer.readAll().map(\.summary) == ["good"])
    }

    @Test func readAllOnAMissingFileReturnsEmptyRatherThanThrowing() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CrashLogWriter(directory: dir).readAll().isEmpty)
    }

    @Test func appendFailurePreservesEarlierRecordsAndDoesNotTrap() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }

        // Write two good records through a normal writer
        let normalWriter = CrashLogWriter(directory: dir)
        normalWriter.append(report("first"))
        normalWriter.append(report("second"))
        #expect(normalWriter.readAll().map(\.summary) == ["first", "second"])

        // Construct a writer with a custom appendBytes that always throws
        let failingAppendBytes: (Data, URL) throws -> Void = { _, _ in
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated write failure"])
        }
        let failingWriter = CrashLogWriter(directory: dir, appendBytes: failingAppendBytes)

        // This append should not trap; it logs the failure and continues
        failingWriter.append(report("third"))

        // The earlier good records should still be readable
        #expect(failingWriter.readAll().map(\.summary) == ["first", "second"])
    }
}
