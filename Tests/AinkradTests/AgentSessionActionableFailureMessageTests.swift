// Tests/AinkradTests/AgentSessionActionableFailureMessageTests.swift
//
// Fix 3: a turn that fails to connect to a LOCAL endpoint (a down Ollama/LM
// Studio server) must surface an actionable transcript message instead of the
// generic "Streaming failed: Could not connect to the server." — the exact
// message real users hit when the router (Fix 1, before it existed) picked an
// unreachable local model. Non-local failures, and local failures that aren't
// connectivity-shaped (e.g. auth errors), must pass through unchanged.
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession.actionableFailureMessage")
struct AgentSessionActionableFailureMessageTests {
    private let connection = Connection(
        id: UUID(), presetID: "ollama", kind: .openAICompatible,
        displayName: "Ollama", baseURL: "http://localhost:11434", createdAt: Date())
    private let remote = Connection(
        id: UUID(), presetID: "claude", kind: .claude,
        displayName: "Claude", baseURL: "https://api.anthropic.com/v1", createdAt: Date())

    @Test func localConnectionFailureYieldsActionableMessage() {
        let message = AgentSession.actionableFailureMessage(
            "Streaming failed: Could not connect to the server.", connection: connection, isLocal: true)

        #expect(message.contains("localhost:11434"))
        #expect(message.contains("Start Ollama/LM Studio"))
        #expect(message.contains("/model"))
    }

    @Test func remoteConnectionFailureStaysGeneric() {
        let original = "Streaming failed: Could not connect to the server."
        let message = AgentSession.actionableFailureMessage(original, connection: remote, isLocal: false)

        #expect(message == original)
    }

    @Test func localConnectionNonConnectivityFailureStaysGeneric() {
        // An auth error on a local connection isn't "server not running" — the
        // actionable "start the server" message would be actively misleading.
        let original = "401 Unauthorized"
        let message = AgentSession.actionableFailureMessage(original, connection: connection, isLocal: true)

        #expect(message == original)
    }
}
