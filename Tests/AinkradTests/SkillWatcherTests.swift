import Foundation
import Testing

@testable import Ainkrad

/// `SkillWatcher` wraps a `DispatchSource.makeFileSystemObjectSource` on the
/// `Skills/` directory fd. Real FS-event delivery is inherently timing-dependent
/// (mirrors Slice 1's deferred FSEvents treatment), so these tests exercise:
///   (1) lifecycle safety (start/stop/deinit; missing directory) on a real temp
///       dir without asserting on a live kernel event, and
///   (2) the debounce/coalescing logic directly via the injectable signal path
///       (`scheduleReload()`), independent of the OS event source, so the test
///       is deterministic rather than sleep-and-hope.
@Suite("SkillWatcher")
@MainActor
struct SkillWatcherTests {
    @Test func startStopIsSafeOnRealDirectory() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swtch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var fired = 0
        let watcher = SkillWatcher(paths: SkillPaths(root: root)) { fired += 1 }
        watcher.start()
        watcher.stop()
        #expect(fired >= 0)  // no crash; reload contract itself is proven in SkillRegistryTests
    }

    @Test func startIsSafeWhenDirectoryIsMissing() {
        // Directory does not exist yet — start() must create it (or otherwise
        // not crash) so the source can open once the user's first skill lands.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swtch-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let watcher = SkillWatcher(paths: SkillPaths(root: root)) {}
        watcher.start()
        #expect(FileManager.default.fileExists(atPath: root.path))
        watcher.stop()
    }

    @Test func stopIsIdempotentAndSafeWithoutStart() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swtch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = SkillWatcher(paths: SkillPaths(root: root)) {}
        watcher.stop()  // never started
        watcher.start()
        watcher.stop()
        watcher.stop()  // idempotent
    }

    @Test(.timeLimit(.minutes(1)))
    func singleChangeFiresExactlyOneReloadAfterDebounce() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swtch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var fired = 0
        let watcher = SkillWatcher(paths: SkillPaths(root: root)) { fired += 1 }

        // Directly invoke the coalescing handler — the unit under test is the
        // debounce logic itself, not kernel FS-event delivery/timing.
        watcher.simulateChange()
        #expect(fired == 0)  // debounced, not yet fired

        await watcher.waitForPendingReload()
        #expect(fired == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func rapidBurstCoalescesToOneReload() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swtch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var fired = 0
        let watcher = SkillWatcher(paths: SkillPaths(root: root)) { fired += 1 }

        for _ in 0..<25 {
            watcher.simulateChange()
        }
        #expect(fired == 0)

        await watcher.waitForPendingReload()
        #expect(fired == 1)  // bounded — one reload for the whole burst, not 25
    }

    @Test
    func stopCancelsPendingDebounceWithoutFiring() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swtch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var fired = 0
        let watcher = SkillWatcher(paths: SkillPaths(root: root)) { fired += 1 }

        watcher.simulateChange()
        watcher.stop()
        // Give the (cancelled) debounce window time to elapse; it must not fire.
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(fired == 0)
    }
}
