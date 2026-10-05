import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomCommandStore")
@MainActor
struct CustomCommandStoreTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ccs-\(UUID().uuidString)")
    }
    private func write(_ body: String, name: String, at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body.write(to: root.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
    }

    @Test func loadsValidCommands() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try write("Fix $ARGUMENTS", name: "fix", at: user)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        #expect(store.all().map(\.name) == ["fix"])
        #expect(store.all().first?.body == "Fix $ARGUMENTS")
    }

    @Test func rejectsReservedAndUnsafeNames() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try write("x", name: "new", at: user)  // builtin -> dropped
        try write("x", name: "Bad Name", at: user)  // unsafe slug -> dropped
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        #expect(store.all().isEmpty)
    }

    @Test func projectOverridesUserOnNameCollision() throws {
        let user = temp()
        let project = temp()
        defer {
            try? FileManager.default.removeItem(at: user)
            try? FileManager.default.removeItem(at: project)
        }
        try write("USER version", name: "ship", at: user)
        try write("PROJECT version", name: "ship", at: project)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: project))
        let ship = store.all().first { $0.name == "ship" }
        #expect(ship?.scope == .project)
        #expect(ship?.body == "PROJECT version")
    }
}
