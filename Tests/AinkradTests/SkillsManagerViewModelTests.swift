import AinkradHostRuntime
// Tests/AinkradTests/SkillsManagerViewModelTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillsManagerViewModel")
@MainActor
struct SkillsManagerViewModelTests {
    private func makeSkill(_ registry: SkillRegistry, name: String, description: String = "does a thing") throws {
        try registry.writeLocal("---\nname: \(name)\ndescription: \(description)\n---\nBody for \(name).", name: name)
    }

    private func make() -> (SkillRegistry, SkillCommandStore, CommandRegistry, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("smvm-\(UUID().uuidString)")
        let registry = SkillRegistry(paths: SkillPaths(root: root))
        let store = SkillCommandStore(persistence: InMemoryPersistenceStore())
        let commandRegistry = CommandRegistry(builtins: [
            SlashCommand(name: "new", summary: "", usage: "/new") { _, _ in .handled(note: nil) }
        ])
        return (registry, store, commandRegistry, root)
    }

    // MARK: - Bind/unbind re-syncs the live CommandRegistry (Task 13's critical follow-up)

    @Test func bindingANewCommandAtRuntimeRegistersItImmediately() throws {
        let (registry, store, commandRegistry, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSkill(registry, name: "deploy")

        // Not registered yet — mirrors the Task 12 gap: bootstrap only ran once.
        #expect(commandRegistry.parse("/ship") == nil)

        let vm = SkillsManagerViewModel(
            registry: registry, store: store,
            resyncCommands: { [store] in
                for cmd in store.slashCommands(registry: registry) { commandRegistry.register(cmd) }
            })
        #expect(vm.bind(command: "ship", toSkill: "deploy"))

        // The freshly-bound command now resolves through the SAME live registry,
        // without needing to reconstruct or relaunch anything.
        let session = TestSessionFactory.make()
        let result = commandRegistry.run("/ship v1", on: session)
        #expect(result == .handled(note: nil))
        #expect(session.messages.last?.text == "Body for deploy.\n\nArguments: v1")
    }

    @Test func unbindingRemovesTheCommandFromTheLiveRegistry() throws {
        let (registry, store, commandRegistry, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSkill(registry, name: "deploy")

        var registeredNames: Set<String> = []
        let resync: () -> Void = { [store] in
            for name in registeredNames { commandRegistry.unregister(name: name) }
            let commands = store.slashCommands(registry: registry)
            for cmd in commands { commandRegistry.register(cmd) }
            registeredNames = Set(commands.map(\.name))
        }
        let vm = SkillsManagerViewModel(registry: registry, store: store, resyncCommands: resync)

        #expect(vm.bind(command: "ship", toSkill: "deploy"))
        #expect(commandRegistry.parse("/ship") != nil)

        vm.unbind("ship")
        #expect(commandRegistry.parse("/ship") == nil)
    }

    @Test func bindRejectsABuiltinShadowingNameAndSurfacesAnError() throws {
        let (registry, store, commandRegistry, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSkill(registry, name: "deploy")
        var resyncCalled = false
        let vm = SkillsManagerViewModel(registry: registry, store: store, resyncCommands: { resyncCalled = true })

        #expect(!vm.bind(command: "new", toSkill: "deploy"))
        #expect(vm.bindError != nil)
        #expect(store.all().isEmpty)
        #expect(!resyncCalled)
        #expect(commandRegistry.parse("/new") != nil)  // builtin untouched
    }

    @Test func bindRejectsAnUnsafeNameAndSurfacesAnError() throws {
        let (registry, store, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSkill(registry, name: "deploy")
        let vm = SkillsManagerViewModel(registry: registry, store: store, resyncCommands: {})

        #expect(!vm.bind(command: "Not Safe", toSkill: "deploy"))
        #expect(vm.bindError?.contains("Not Safe") == true)
        #expect(store.all().isEmpty)
    }

    @Test func deletingASkillReSyncsSoItsBoundCommandBecomesBroken() throws {
        let (registry, store, commandRegistry, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSkill(registry, name: "deploy")

        var registeredNames: Set<String> = []
        let resync: () -> Void = { [store] in
            for name in registeredNames { commandRegistry.unregister(name: name) }
            let commands = store.slashCommands(registry: registry)
            for cmd in commands { commandRegistry.register(cmd) }
            registeredNames = Set(commands.map(\.name))
        }
        let vm = SkillsManagerViewModel(registry: registry, store: store, resyncCommands: resync)
        #expect(vm.bind(command: "ship", toSkill: "deploy"))

        let skill = try #require(registry.skill(named: "deploy"))
        vm.delete(skill)

        #expect(registry.skill(named: "deploy") == nil)
        let result = commandRegistry.run("/ship", on: TestSessionFactory.make())
        guard case .handled(let note) = result, let note else {
            Issue.record("expected a broken-binding note")
            return
        }
        #expect(note.contains("deploy"))
    }

    // MARK: - Local skill editor

    @Test func saveWritesTheDraftAndClearsUnsavedState() throws {
        let (registry, store, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSkill(registry, name: "deploy")
        let vm = SkillsManagerViewModel(registry: registry, store: store, resyncCommands: {})
        let skill = try #require(registry.skill(named: "deploy"))

        vm.setDraft("---\nname: deploy\ndescription: updated\n---\nNew body.", for: skill)
        #expect(vm.hasUnsavedChanges(skill))
        vm.save(skill)
        #expect(!vm.hasUnsavedChanges(skill))
        #expect(registry.skill(named: "deploy")?.description == "updated")
    }
}
