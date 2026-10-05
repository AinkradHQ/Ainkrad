import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("AgentContextService")
struct AgentContextServiceTests {
    @Test("both toggles on by default: assembled context includes all snapshots")
    func bothEnabledByDefault() {
        let hub = AgentContextRegistryHub()
        let terminal = HostContextRegistry(appID: "terminal", hub: hub)
        let git = HostContextRegistry(appID: "gitmage", hub: hub)
        _ = terminal.register { AgentContextSnapshot(kind: "terminal", title: "Terminal — ~/proj", text: "buf") }
        _ = git.register { AgentContextSnapshot(kind: "git", title: "Git — main", text: "clean") }

        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        let service = AgentContextService(hub: hub, settings: settings)
        let result = service.assembleContext()

        #expect(result.contains("Terminal — ~/proj"))
        #expect(result.contains("buf"))
        #expect(result.contains("Git — main"))
        #expect(result.contains("clean"))
        #expect(result.hasPrefix("<workspace_context>"))
        #expect(result.hasSuffix("</workspace_context>"))
    }

    @Test("terminal disabled: assembled context excludes terminal but keeps git")
    func terminalDisabled() {
        let hub = AgentContextRegistryHub()
        let terminal = HostContextRegistry(appID: "terminal", hub: hub)
        let git = HostContextRegistry(appID: "gitmage", hub: hub)
        _ = terminal.register { AgentContextSnapshot(kind: "terminal", title: "Terminal — ~/proj", text: "buf") }
        _ = git.register { AgentContextSnapshot(kind: "git", title: "Git — main", text: "clean") }

        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setEnabled(false, for: "terminal")
        let service = AgentContextService(hub: hub, settings: settings)
        let result = service.assembleContext()

        #expect(result.contains("Git — main"))
        #expect(result.contains("clean"))
        #expect(!result.contains("Terminal — ~/proj"))
        #expect(!result.contains("buf"))
    }

    @Test("assistant-memory disabled: assembled context excludes the memory snapshot but keeps git")
    func assistantMemoryDisabled() throws {
        let hub = AgentContextRegistryHub()
        let git = HostContextRegistry(appID: "gitmage", hub: hub)
        _ = git.register { AgentContextSnapshot(kind: "git", title: "Git — main", text: "clean") }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-memory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        memory.write("hi", to: .user, provenance: .remember)
        _ = hub.register(appID: "host.memory") { MemoryContextSource.snapshot(from: memory) }

        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setEnabled(false, for: "assistant-memory")
        let service = AgentContextService(hub: hub, settings: settings)
        let result = service.assembleContext()

        #expect(result.contains("Git — main"))
        #expect(result.contains("clean"))
        #expect(!result.contains("Sage Memory"))
    }

    @Test("oversized snapshot text is truncated with marker")
    func truncatesOversizedText() {
        let hub = AgentContextRegistryHub()
        let terminal = HostContextRegistry(appID: "terminal", hub: hub)
        let oversized = String(repeating: "a", count: 9000)
        _ = terminal.register { AgentContextSnapshot(kind: "terminal", title: "Terminal — ~/proj", text: oversized) }

        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        let service = AgentContextService(hub: hub, settings: settings)
        let result = service.assembleContext()

        #expect(result.contains("…[truncated]"))
        #expect(!result.contains(oversized))
        // The full 9000-char run must not survive intact; only a prefix up to
        // the per-source budget should be embedded.
        let perSourceCharBudget = 8000
        let truncatedRun = String(repeating: "a", count: perSourceCharBudget)
        #expect(result.contains(truncatedRun))
        let fullRunPlusOne = String(repeating: "a", count: perSourceCharBudget + 1)
        #expect(!result.contains(fullRunPlusOne))
    }

    @Test("empty hub yields empty string")
    func emptyHub() {
        let hub = AgentContextRegistryHub()
        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        let service = AgentContextService(hub: hub, settings: settings)
        #expect(service.assembleContext() == "")
    }
}
