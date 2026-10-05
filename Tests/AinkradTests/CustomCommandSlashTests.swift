import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomCommand slash commands")
@MainActor
struct CustomCommandSlashTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ccsl-\(UUID().uuidString)")
    }

    @Test func buildsOneSlashCommandPerCommandInCustomCategory() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "Fix $ARGUMENTS".write(
            to: user.appendingPathComponent("fix.md"),
            atomically: true, encoding: .utf8)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        let slash = store.slashCommands()
        #expect(slash.map(\.name) == ["fix"])
        #expect(slash.first?.category == .custom)
    }

    @Test func customCategoryHasStableTitleAndOrder() {
        #expect(CommandCategory.custom.title == "Commands")
        #expect(CommandCategory.custom.order == 5)
        #expect(CommandCategory.other.order == 6)
    }

    @Test func runningCommandIsHandled() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "Deploy $1".write(
            to: user.appendingPathComponent("ship.md"),
            atomically: true, encoding: .utf8)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        let reg = CommandRegistry(builtins: [])
        for c in store.slashCommands() { reg.register(c) }
        let result = reg.run("/ship staging", on: TestSessionFactory.make())
        #expect(result == .handled(note: nil))
    }
}
