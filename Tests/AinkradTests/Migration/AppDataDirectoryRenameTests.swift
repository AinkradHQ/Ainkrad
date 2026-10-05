import Foundation
import Testing

@testable import AinkradHostRuntime

@Suite("AppDataDirectoryRename")
struct AppDataDirectoryRenameTests {
    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("moves a retired app's directory and its contents")
    func movesDirectory() throws {
        let root = try makeRoot()
        let old = root.appending(path: "files")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("tabs".utf8).write(to: old.appending(path: "panes.bin"))

        AppDataDirectoryRename.run(root: root, fileManager: .default)

        let moved = root.appending(path: "hoard/panes.bin")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test("leaves an unrelated app's directory alone")
    func leavesOthersAlone() throws {
        let root = try makeRoot()
        let other = root.appending(path: "leyline")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        AppDataDirectoryRename.run(root: root, fileManager: .default)

        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test("does not clobber an existing new-id directory")
    func doesNotClobber() throws {
        let root = try makeRoot()
        let old = root.appending(path: "files")
        let new = root.appending(path: "hoard")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("current".utf8).write(to: new.appending(path: "panes.bin"))

        AppDataDirectoryRename.run(root: root, fileManager: .default)

        let kept = try Data(contentsOf: new.appending(path: "panes.bin"))
        #expect(String(decoding: kept, as: UTF8.self) == "current")
        // The old directory is left in place rather than deleted — nothing is
        // destroyed on a path we cannot reason about.
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test("is a no-op when the root does not exist yet")
    func noOpOnFreshInstall() {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        AppDataDirectoryRename.run(root: root, fileManager: .default)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
