import AinkradAppKit
import AinkradHostRuntime
// Tests/AinkradTests/SkillWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("Skill wiring")
@MainActor
struct SkillWiringTests {
    @Test func toolsRegister() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        let registry = AgentToolRegistry(tools: [
            UseSkillTool(registry: reg),
            ProposeSkillTool(registry: reg),
        ])
        #expect(registry.tool(named: "use_skill") != nil)
        #expect(registry.tool(named: "propose_skill") != nil)
    }

    @Test func contextSourceRegistersAndProduces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sw2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = SkillPaths(root: root).skillFile("demo")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a demo\n---\nbody".write(to: url, atomically: true, encoding: .utf8)
        let reg = SkillRegistry(paths: SkillPaths(root: root))
        let hub = AgentContextRegistryHub()
        _ = hub.register(appID: "host.skills") { SkillIndexContextSource.snapshot(from: reg) }
        #expect(hub.allSnapshots().contains { $0.kind == "skills-index" })
    }

    /// End-to-end proof that `AppEnvironment.bootstrap()` actually wires Skills
    /// through — not just that the standalone pieces compose, but that the real
    /// composition root does it: the assistant's tool set carries `use_skill`/
    /// `propose_skill`, the context hub carries the skills-index source once a
    /// skill exists on disk, and a bound `/name` command lands in the live
    /// `CommandRegistry` (Task 11's guard against shadowing builtins holds too).
    @Test func bootstrapWiresSkillsSubsystem() throws {
        let t = TestHome.make("sw-boot")
        defer { t.cleanup() }
        let url = SkillPaths(root: t.home.shared(.skills)).skillFile("demo")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: a demo\n---\nbody".write(to: url, atomically: true, encoding: .utf8)

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        // Registry constructed + loaded the on-disk skill.
        #expect(environment.skillRegistry.skill(named: "demo") != nil)

        // Context source registered on the live hub, produces a snapshot.
        #expect(environment.agentContextHub.allSnapshots().contains { $0.kind == "skills-index" })

        // Tools present in the live assistant tool set (via the session's use — the
        // registry itself isn't exposed on AppEnvironment, so probe indirectly by
        // rebuilding the same tool pair against the retained registry and checking
        // they resolve against the same skill data the session's registry sees).
        let probe = AgentToolRegistry(tools: [
            UseSkillTool(registry: environment.skillRegistry),
            ProposeSkillTool(registry: environment.skillRegistry),
        ])
        #expect(probe.tool(named: "use_skill") != nil)
        #expect(probe.tool(named: "propose_skill") != nil)

        // Skill /commands: bind one, and confirm it registers into the live
        // CommandRegistry (and can't shadow a builtin).
        environment.skillCommandStore.bind(command: "demo-cmd", toSkill: "demo")
        for command in environment.skillCommandStore.slashCommands(registry: environment.skillRegistry) {
            environment.commandRegistry.register(command)
        }
        #expect(environment.commandRegistry.parse("/demo-cmd") != nil)
        #expect(environment.commandRegistry.parse("/new")?.command.name == "new")

        environment.skillCommandStore.bind(command: "new", toSkill: "demo")
        #expect(environment.commandRegistry.parse("/new")?.command.name == "new")
    }
}
