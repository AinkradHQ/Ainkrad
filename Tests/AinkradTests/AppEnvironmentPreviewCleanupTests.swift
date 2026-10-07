import Foundation
import Testing

@testable import Ainkrad

/// Guards the fix for the leak found in Task 3 review round 1: `preview()`
/// used to create a fresh temp directory + `UserDefaults` suite on every
/// call and never remove either, so a suite calling it repeatedly (as every
/// later settings-catalog task's tests do) would accumulate throwaway state
/// for the whole process lifetime. Isolation between calls must stay intact
/// — see `AppEnvironment.preview()`'s doc comment — so this only asserts the
/// on-disk footprint is reclaimed once a preview environment deallocates,
/// not that two previews ever share storage.
@Suite("AppEnvironment.preview() cleanup")
@MainActor
struct AppEnvironmentPreviewCleanupTests {
    @Test("temp directories created by preview() are removed once the environment deallocates")
    func previewTempDirectoriesAreReclaimed() {
        let tmp = FileManager.default.temporaryDirectory
        func previewDirCount() -> Int {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
            return names.filter { $0.hasPrefix("AinkradPreview-") }.count
        }

        let before = previewDirCount()

        // Several calls, each dropped immediately — mirrors how a catalog
        // test suite calls `.preview()` per `@Test`. If cleanup only fired
        // for the last call, or not at all, this count would climb.
        for _ in 0..<5 {
            _ = AppEnvironment.preview()
        }

        let after = previewDirCount()
        #expect(
            after == before, "expected no net growth in AinkradPreview-* temp directories, saw \(before) -> \(after)")
    }
}
