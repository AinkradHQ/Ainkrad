import Foundation
import Testing

@testable import AinkradHostRuntime

@Suite("RetiredPluginBundleCleanup")
struct RetiredPluginBundleCleanupTests {
    private func makeDir() throws -> URL {
        let d = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func makeBundle(_ name: String, in dir: URL) throws -> URL {
        let b = dir.appending(path: name)
        try FileManager.default.createDirectory(
            at: b.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        return b
    }

    @Test("removes a bundle installed under a retired app id")
    func removesRetiredBundle() throws {
        let dir = try makeDir()
        let retired = try makeBundle("terminal.bundle", in: dir)

        RetiredPluginBundleCleanup.run(pluginsDirectories: [dir])

        #expect(!FileManager.default.fileExists(atPath: retired.path))
    }

    @Test("leaves a current bundle alone")
    func leavesCurrentBundles() throws {
        let dir = try makeDir()
        let kept = try makeBundle("gitmage.bundle", in: dir)
        let renamed = try makeBundle("rune.bundle", in: dir)

        RetiredPluginBundleCleanup.run(pluginsDirectories: [dir])

        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    /// The duplicate this exists to prevent: the installer writes and removes
    /// `<appID>.bundle`, so installing Rune beside a leftover terminal.bundle
    /// leaves two bundles that both load.
    @Test("a retired bundle cannot survive beside its replacement")
    func noDuplicateAfterUpgrade() throws {
        let dir = try makeDir()
        _ = try makeBundle("terminal.bundle", in: dir)
        _ = try makeBundle("rune.bundle", in: dir)

        RetiredPluginBundleCleanup.run(pluginsDirectories: [dir])

        let remaining = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".bundle") }
        #expect(remaining == ["rune.bundle"])
    }

    @Test("is a no-op on a directory that does not exist")
    func noOpOnMissingDirectory() {
        let missing = URL.temporaryDirectory.appending(path: UUID().uuidString)
        RetiredPluginBundleCleanup.run(pluginsDirectories: [missing])
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
