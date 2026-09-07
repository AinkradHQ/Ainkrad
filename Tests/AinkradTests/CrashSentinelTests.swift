import Foundation
import Testing
@testable import Ainkrad

/// These tests mutate global process state (`NSSetUncaughtExceptionHandler`),
/// so the suite is serialized and every test captures/restores the previous
/// handler to avoid bleeding into other tests in the same process.
@Suite("CrashSentinel", .serialized)
struct CrashSentinelTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashSentinelTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func installedHandlerRecordsAnUncaughtException() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let writer = CrashLogWriter(directory: dir)
        let previousHandler = NSGetUncaughtExceptionHandler()
        defer { NSSetUncaughtExceptionHandler(previousHandler) }

        CrashSentinel.install(writer: writer)

        let handler = NSGetUncaughtExceptionHandler()
        #expect(handler != nil)

        let exception = NSException(
            name: .genericException,
            reason: "sentinel smoke",
            userInfo: nil
        )
        handler?(exception)

        let reports = writer.readAll()
        let match = reports.first { $0.kind == .uncaughtException }
        #expect(match != nil)
        #expect(match?.summary == NSExceptionName.genericException.rawValue)
        #expect(match?.detail == "sentinel smoke")
    }
}
