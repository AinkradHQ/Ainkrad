import AinkradHostRuntime
// Tests/AinkradTests/SkillCommandTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("Skill /commands")
@MainActor
struct SkillCommandTests {
    private func make() throws -> (SkillCommandStore, SkillRegistry, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString)")
        let url = SkillPaths(root: root).skillFile("deploy")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "---\nname: deploy\ndescription: ship\n---\nRun make release.".write(
            to: url, atomically: true, encoding: .utf8)
        let store = SkillCommandStore(persistence: InMemoryPersistenceStore())
        return (store, SkillRegistry(paths: SkillPaths(root: root)), root)
    }

    // MARK: - Store

    @Test func bindPersistsAndLooksUp() throws {
        let (store, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        #expect(store.skillName(forCommand: "ship") == "deploy")
        #expect(store.all() == [SkillCommandBinding(command: "ship", skillName: "deploy")])
    }

    @Test func bindReplacesExistingBindingForSameCommand() throws {
        let (store, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        store.bind(command: "ship", toSkill: "other-skill")
        #expect(store.skillName(forCommand: "ship") == "other-skill")
        #expect(store.all().count == 1)
    }

    @Test func unbindRemovesTheBinding() throws {
        let (store, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        store.unbind(command: "ship")
        #expect(store.skillName(forCommand: "ship") == nil)
        #expect(store.all().isEmpty)
    }

    @Test func bindPersistsAcrossStoreInstancesSharingAPersistenceStore() throws {
        let persistence = InMemoryPersistenceStore()
        let store1 = SkillCommandStore(persistence: persistence)
        store1.bind(command: "ship", toSkill: "deploy")
        let store2 = SkillCommandStore(persistence: persistence)
        #expect(store2.skillName(forCommand: "ship") == "deploy")
    }

    @Test func bindRejectsUnsafeCommandNames() throws {
        let (store, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "not safe", toSkill: "deploy")
        store.bind(command: "Ship", toSkill: "deploy")
        store.bind(command: "a/b", toSkill: "deploy")
        #expect(store.all().isEmpty)
    }

    @Test func bindRejectsNamesThatCollideWithABuiltin() throws {
        let (store, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        for builtin in ["new", "reset", "remember", "model", "think", "verbose", "trace", "usage", "compact", "export"]
        {
            store.bind(command: builtin, toSkill: "deploy")
        }
        #expect(store.all().isEmpty)
        #expect(
            BuiltinCommands.reservedNames.isSuperset(of: [
                "new", "reset", "remember", "model", "think", "verbose", "trace", "usage", "compact", "export",
            ]))
    }

    @Test func skillCommandsDocumentDecodesForwardCompatiblyWhenBindingsKeyIsMissing() throws {
        let data = Data("{}".utf8)
        let decoded = try PersistenceCoding.decoder.decode(SkillCommandsDocument.self, from: data)
        #expect(decoded.bindings.isEmpty)
    }

    // MARK: - Resolver

    @Test func resolveBoundCommandComposesPromptWithArgs() throws {
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        let r = SkillCommandResolver.resolve("/ship v1.2.0", store: store, registry: reg)
        guard case .prompt(let text) = r else {
            Issue.record("expected .prompt")
            return
        }
        #expect(text.contains("Run make release."))  // skill body
        #expect(text.contains("v1.2.0"))  // args appended
    }

    @Test func resolveBoundCommandWithNoArgsOmitsArgumentsSection() throws {
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        let r = SkillCommandResolver.resolve("/ship", store: store, registry: reg)
        guard case .prompt(let text) = r else {
            Issue.record("expected .prompt")
            return
        }
        #expect(text == "Run make release.")
    }

    @Test func brokenBindingWhenSkillMissing() throws {
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "gone", toSkill: "deleted-skill")
        #expect(
            SkillCommandResolver.resolve("/gone now", store: store, registry: reg)
                == .brokenBinding(command: "gone", missingSkill: "deleted-skill"))
    }

    @Test func unboundSlashIsNotASkillCommand() throws {
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SkillCommandResolver.resolve("/compact", store: store, registry: reg) == .notASkillCommand)
        #expect(SkillCommandResolver.resolve("just a message", store: store, registry: reg) == .notASkillCommand)
    }

    // MARK: - CommandRegistry integration (Slice 5 merged path)

    @Test func registeredSkillCommandDispatchesComposedPromptThroughTheSession() throws {
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        let registry = CommandRegistry(builtins: [])
        for cmd in store.slashCommands(registry: reg) { registry.register(cmd) }

        let session = TestSessionFactory.make(commands: registry)
        let result = registry.run("/ship v1.2.0", on: session)
        #expect(result == .handled(note: nil))
        #expect(session.messages.last?.text == "Run make release.\n\nArguments: v1.2.0")
    }

    @Test func registeredSkillCommandSurfacesABrokenBindingNoteWithoutCrashing() throws {
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "gone", toSkill: "deleted-skill")
        let registry = CommandRegistry(builtins: [])
        for cmd in store.slashCommands(registry: reg) { registry.register(cmd) }

        let session = TestSessionFactory.make(commands: registry)
        let result = registry.run("/gone now", on: session)
        guard case .handled(let note) = result, let note else {
            Issue.record("expected handled note")
            return
        }
        #expect(note.contains("deleted-skill"))
        #expect(session.messages.isEmpty)  // never sent as a turn
    }

    @Test func slashCommandsNeverShadowABuiltinEvenIfSomehowBound() throws {
        // Defense in depth: `bind` already refuses builtin-colliding names, but
        // `slashCommands(registry:)` must independently filter them too, so a
        // stray persisted binding (e.g. from an older/buggy build) can never
        // register over a builtin.
        let (store, reg, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.bind(command: "ship", toSkill: "deploy")
        #expect(store.slashCommands(registry: reg).map(\.name) == ["ship"])
    }
}
