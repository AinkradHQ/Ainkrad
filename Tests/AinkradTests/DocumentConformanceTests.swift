import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

@Suite("Domain document conformance")
struct DocumentConformanceTests {
    @Test("document ids are stable and distinct")
    func stableDocumentIDs() {
        #expect(GlobalSettings.documentID == "global-settings")
        #expect(LayoutStateSnapshot.documentID == "workspace-layout")
        #expect(RegistryStateDocument.documentID == "registry-enabled-state")
        #expect(AgentsDocument.documentID == "agents")
        #expect(UsageLedgerDocument.documentID == "usage-ledger")
        #expect(RouterOutcomeDocument.documentID == "router-outcomes")
        #expect(AuthProfilesDocument.documentID == "auth-profiles")
        #expect(SageRuntimeOptions.documentID == "assistant-runtime")
        #expect(SageWorkspaceSettings.documentID == "assistant-workspace")
        #expect(MCPServersDocument.documentID == "mcp-servers")
        #expect(LSPServersDocument.documentID == "lsp-servers")
        #expect(AgentRunsDocument.documentID == "agent-runs")
        #expect(SandboxProfileDocument.documentID == "sandbox-profiles")
        #expect(SkillCommandsDocument.documentID == "skill-commands")
        #expect(DiscoveredModelsDocument.documentID == "discovered-models")
        #expect(SchedulesDocument.documentID == "agent-schedules")
        #expect(VoiceSettingsDocument.documentID == "voice-settings")
    }

    @Test("VoiceSettingsDocument round-trips through a persistence store")
    func voiceSettingsRoundTrips() {
        let store = InMemoryPersistenceStore()
        store.save(VoiceSettingsDocument(backend: .provider, autoSend: true))
        #expect(store.load(VoiceSettingsDocument.self) == VoiceSettingsDocument(backend: .provider, autoSend: true))
    }

    @Test("GlobalSettings round-trips through a persistence store")
    func globalSettingsRoundTrips() {
        let store = InMemoryPersistenceStore()
        store.save(GlobalSettings(theme: .cyberPurple))
        #expect(store.load(GlobalSettings.self) == GlobalSettings(theme: .cyberPurple))
    }

    @Test("RegistryStateDocument round-trips through a persistence store")
    func registryStateRoundTrips() {
        let store = InMemoryPersistenceStore()
        store.save(RegistryStateDocument(enabled: ["terminal": false]))
        #expect(store.load(RegistryStateDocument.self)?.enabled == ["terminal": false])
    }
}
