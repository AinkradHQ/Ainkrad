import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomCommandWatcher")
@MainActor
struct CustomCommandWatcherTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ccw-\(UUID().uuidString)")
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadReRegistersAfterFileAppears() async throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        let reg = CommandRegistry(builtins: [])
        var known = resyncCustomCommands(store: store, registry: reg, previous: [])
        #expect(reg.all().isEmpty)

        try "Fix $ARGUMENTS".write(
            to: user.appendingPathComponent("fix.md"),
            atomically: true, encoding: .utf8)
        let watcher = CustomCommandWatcher(directory: user) {
            store.reload()
            known = resyncCustomCommands(store: store, registry: reg, previous: known)
        }
        watcher.simulateChange()
        await watcher.waitForPendingReload()
        #expect(reg.all().contains { $0.name == "fix" })
        watcher.stop()
    }

    @Test func resyncDropsStaleNames() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "x".write(to: user.appendingPathComponent("gone.md"), atomically: true, encoding: .utf8)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        let reg = CommandRegistry(builtins: [])
        let known = resyncCustomCommands(store: store, registry: reg, previous: [])
        #expect(reg.all().contains { $0.name == "gone" })
        try FileManager.default.removeItem(at: user.appendingPathComponent("gone.md"))
        store.reload()
        _ = resyncCustomCommands(store: store, registry: reg, previous: known)
        #expect(!reg.all().contains { $0.name == "gone" })
    }

    private func skillReview() -> SlashCommand {
        SlashCommand(name: "review", summary: "SKILL review", usage: "/review") { _, _ in .handled(note: nil) }
    }

    @Test func customDoesNotShadowAnExistingRegisteredCommand() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "Do a review".write(to: user.appendingPathComponent("review.md"), atomically: true, encoding: .utf8)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        let reg = CommandRegistry(builtins: [])
        reg.register(skillReview())

        let live = resyncCustomCommands(store: store, registry: reg, previous: [])

        #expect(!live.contains("review"))
        let registered = reg.all().first { $0.name == "review" }
        #expect(registered?.summary == "SKILL review")
    }

    @Test func resyncDoesNotUnregisterANameItDidNotRegister() throws {
        let user = temp()
        defer { try? FileManager.default.removeItem(at: user) }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "Do a review".write(to: user.appendingPathComponent("review.md"), atomically: true, encoding: .utf8)
        let store = CustomCommandStore(paths: CustomCommandPaths(userRoot: user, projectRoot: nil))
        let reg = CommandRegistry(builtins: [])
        reg.register(skillReview())

        let known = resyncCustomCommands(store: store, registry: reg, previous: [])
        #expect(reg.all().first { $0.name == "review" }?.summary == "SKILL review")

        try FileManager.default.removeItem(at: user.appendingPathComponent("review.md"))
        store.reload()
        _ = resyncCustomCommands(store: store, registry: reg, previous: known)

        let stillThere = reg.all().first { $0.name == "review" }
        #expect(stillThere != nil)
        #expect(stillThere?.summary == "SKILL review")
    }
}
