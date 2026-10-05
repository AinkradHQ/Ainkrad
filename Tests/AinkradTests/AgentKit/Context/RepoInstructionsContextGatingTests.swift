import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor @Suite struct RepoInstructionsContextGatingTests {
    private func makeRepo() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("Prefer small PRs.".utf8).write(to: base.appendingPathComponent("CLAUDE.md"))
        return base
    }

    @Test func includedWhenEnabledAndLabeledDistinctly() throws {
        let root = try makeRepo()
        let hub = AgentContextRegistryHub()
        let loader = RepoInstructionsLoader(root: root)
        _ = hub.register(appID: "host.repo-instructions") { loader.snapshot() }
        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        let service = AgentContextService(hub: hub, settings: settings)

        let ctx = service.assembleContext()
        #expect(ctx.contains("<workspace_context>"))
        #expect(ctx.contains("## Repository Instructions"))
        #expect(ctx.contains("Prefer small PRs."))
    }

    @Test func excludedWhenPrivacyOptedOut() throws {
        let root = try makeRepo()
        let hub = AgentContextRegistryHub()
        let loader = RepoInstructionsLoader(root: root)
        _ = hub.register(appID: "host.repo-instructions") { loader.snapshot() }
        let settings = AgentContextSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setEnabled(false, for: RepoInstructionsLoader.kind)
        let service = AgentContextService(hub: hub, settings: settings)

        #expect(!service.assembleContext().contains("Repository Instructions"))
    }
}
