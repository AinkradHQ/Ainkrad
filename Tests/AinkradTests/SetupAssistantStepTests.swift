import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup assistant step")
@MainActor
struct SetupAssistantStepTests {
    @Test func choosingABuiltInAgentMakesItActive() {
        let t = TestHome.make("agent")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupAssistant.apply(
            profile: BuiltInAgents.plan, model: "claude-opus-4-8",
            effort: "xhigh", agents: env.agentStore, config: env.agentConfigStore)

        #expect(env.agentStore.active.id == BuiltInAgents.plan.id)
        #expect(env.agentConfigStore.current.model == "claude-opus-4-8")
    }

    @Test func acustomPersonaIsAddedThenActivated() {
        let t = TestHome.make("agent2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let custom = AgentProfile.custom(name: "Scribe", instructions: "Be terse.")
        SetupAssistant.apply(
            profile: custom, model: "claude-opus-4-8",
            effort: "high", agents: env.agentStore, config: env.agentConfigStore)

        #expect(env.agentStore.active.name == "Scribe")
        #expect(env.agentConfigStore.current.effort == "high")
    }

    @Test func nonAnthropicConnectionSeedsItsOwnCuratedModelNotTheAnthropicDefault() {
        let t = TestHome.make("agent3")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let openAIPreset = ProviderPreset.preset(id: "openai")
        let connection = env.connectionStore.addConnection(
            preset: openAIPreset, displayName: "OpenAI", baseURL: openAIPreset.defaultBaseURL, token: "sk-test")
        env.agentConfigStore.setActiveConnectionID(connection.id)

        let seeded = SetupAssistant.defaultModel(
            connections: env.connectionStore.connections,
            activeConnectionID: env.agentConfigStore.activeConnectionID)

        #expect(seeded == openAIPreset.curatedModels.first)
        #expect(seeded != "claude-opus-4-8")
    }

    @Test func backThenContinueOnACustomPersonaDoesNotDuplicateIt() {
        let t = TestHome.make("agent4")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let id = UUID()
        let first = AgentProfile(id: id, name: "Scribe", instructions: "Be terse.", toolPolicy: .all)
        SetupAssistant.apply(
            profile: first, model: "claude-opus-4-8",
            effort: "high", agents: env.agentStore, config: env.agentConfigStore)

        // Simulate Back then Continue again on the same persona (same id,
        // possibly edited instructions) rather than a fresh add.
        let second = AgentProfile(id: id, name: "Scribe", instructions: "Be terser.", toolPolicy: .all)
        SetupAssistant.apply(
            profile: second, model: "claude-opus-4-8",
            effort: "high", agents: env.agentStore, config: env.agentConfigStore)

        #expect(env.agentStore.agents.filter { $0.id == id }.count == 1)
        #expect(env.agentStore.active.instructions == "Be terser.")
    }
}
