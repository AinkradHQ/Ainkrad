import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomCommandPaths")
struct CustomCommandPathsTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString)")
    }

    @Test func enumeratesMarkdownFilesWithScope() throws {
        let user = temp()
        let project = temp()
        defer {
            try? FileManager.default.removeItem(at: user)
            try? FileManager.default.removeItem(at: project)
        }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "a".write(to: user.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
        try "b".write(to: user.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)  // ignored
        try "c".write(to: project.appendingPathComponent("beta.md"), atomically: true, encoding: .utf8)

        let paths = CustomCommandPaths(userRoot: user, projectRoot: project)
        let files = paths.commandFiles()
        #expect(files.contains { $0.url.lastPathComponent == "alpha.md" && $0.scope == .user })
        #expect(files.contains { $0.url.lastPathComponent == "beta.md" && $0.scope == .project })
        #expect(!files.contains { $0.url.lastPathComponent == "notes.txt" })
    }

    @Test func nilProjectRootYieldsUserOnly() {
        let paths = CustomCommandPaths(userRoot: temp(), projectRoot: nil)
        #expect(paths.commandFiles().isEmpty)  // dir does not exist -> empty, never crashes
    }

    @Test func projectRootIsDotAinkradCommands() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        #expect(CustomCommandPaths.projectRoot(forWorkspace: ws).path == "/tmp/ws/.ainkrad/commands")
    }
}
