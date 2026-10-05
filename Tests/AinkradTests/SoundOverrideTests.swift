import Foundation
import Testing

@testable import Ainkrad

/// Covers `SoundEngine.resolvedURL`, the pure override-resolution rule behind
/// AIN-108's user-data sound overrides: a same-named wav in the override
/// directory wins over the bundled synth wav, falling back to the bundle
/// (and finally to `nil`) whenever the override isn't present on disk.
@Suite("SoundEngine override resolution")
final class SoundOverrideResolutionTests {
    let root: URL
    let overrideDir: URL
    let bundleDir: URL

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
        overrideDir = root.appendingPathComponent("Sounds", isDirectory: true)
        bundleDir = root.appendingPathComponent("Bundle", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        // The bundled fallback asset actually exists on disk so `Bundle(url:)`
        // can resolve it — override presence itself is driven by the fake
        // `fileExists` closure below, not by real files in `overrideDir`.
        FileManager.default.createFile(atPath: bundleDir.appendingPathComponent("confirm.wav").path, contents: Data())
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    private var bundle: Bundle {
        Bundle(url: bundleDir)!
    }

    @Test("prefers the override URL when fileExists reports it present")
    func overridePresentWins() {
        let overrideURL = overrideDir.appendingPathComponent("confirm.wav")
        let resolved = SoundEngine.resolvedURL(
            for: .confirm,
            overrideDirectory: overrideDir,
            bundle: bundle,
            fileExists: { $0 == overrideURL }
        )
        #expect(resolved == overrideURL)
    }

    @Test("falls back to the bundled asset when the override is absent")
    func overrideAbsentFallsBackToBundle() {
        let resolved = SoundEngine.resolvedURL(
            for: .confirm,
            overrideDirectory: overrideDir,
            bundle: bundle,
            fileExists: { _ in false }
        )
        #expect(resolved == bundleDir.appendingPathComponent("confirm.wav"))
    }

    @Test("returns nil when neither the override nor the bundled asset exists")
    func neitherExistsReturnsNil() {
        let resolved = SoundEngine.resolvedURL(
            for: .error,  // not present in `bundleDir`
            overrideDirectory: overrideDir,
            bundle: bundle,
            fileExists: { _ in false }
        )
        #expect(resolved == nil)
    }

    @Test("a nil override directory always resolves via the bundle, even if fileExists would say yes")
    func nilOverrideDirectoryAlwaysUsesBundle() {
        let resolved = SoundEngine.resolvedURL(
            for: .confirm,
            overrideDirectory: nil,
            bundle: bundle,
            fileExists: { _ in true }  // must be ignored: there's no override path to check
        )
        #expect(resolved == bundleDir.appendingPathComponent("confirm.wav"))
    }
}
