import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("DirectoryWatcher")
struct DirectoryWatcherTests {
    @Test("fires when a file appears in the watched directory", .timeLimit(.minutes(1)))
    func firesOnChange() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A reference box, not a captured `var`: the callback runs on the main
        // actor from FSEvents, and Swift 6 rejects mutating a local from an
        // escaping closure.
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()

        let watcher = DirectoryWatcher(url: root) { flag.fired = true }
        defer { watcher.stop() }

        // FSEvents needs the stream running before the change lands.
        try await Task.sleep(for: .milliseconds(300))
        try "x".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        // The watcher coalesces with a 200ms latency; give it room.
        for _ in 0..<40 where !flag.fired {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(flag.fired)
    }

    @Test("stop is idempotent")
    func stopTwice() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let watcher = DirectoryWatcher(url: root) {}
        watcher.stop()
        watcher.stop()
    }
}
