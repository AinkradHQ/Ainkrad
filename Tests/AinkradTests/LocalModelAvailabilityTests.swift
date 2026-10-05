// Tests/AinkradTests/LocalModelAvailabilityTests.swift
//
// Locks in the assistant-unusable-with-a-down-local-server fix (Fix 1): the
// router's `candidatesProvider` must never pick a LOCAL model whose server
// isn't reachable. Covers both halves: the pure filter
// (`RouterOrdering.filterReachableCandidates`) and the async cache that feeds
// it (`LocalModelAvailability.refresh`).
import Foundation
import Testing

@testable import Ainkrad

@Suite("LocalModelAvailability")
@MainActor
struct LocalModelAvailabilityTests {
    private func candidate(_ connectionID: UUID, model: String, tier: ModelTier) -> RouterCandidate {
        RouterCandidate(
            connectionID: connectionID, model: model,
            descriptor: ModelDescriptor(id: model, tier: tier, contextWindow: 32_000, capabilities: [.toolUse]))
    }

    // MARK: - Pure filter

    @Test func dropsLocalCandidateWhoseConnectionIsNotReachable() {
        let localConnectionID = UUID()
        let candidates = [candidate(localConnectionID, model: "llama3.2", tier: .local)]

        let filtered = RouterOrdering.filterReachableCandidates(
            candidates, reachableLocalConnectionIDs: [],
            isLocalConnection: { _ in true })

        #expect(filtered.isEmpty)
    }

    @Test func keepsLocalCandidateWhoseConnectionIsReachable() {
        let localConnectionID = UUID()
        let candidates = [candidate(localConnectionID, model: "llama3.2", tier: .local)]

        let filtered = RouterOrdering.filterReachableCandidates(
            candidates, reachableLocalConnectionIDs: [localConnectionID],
            isLocalConnection: { _ in true })

        #expect(filtered.map(\.model) == ["llama3.2"])
    }

    @Test func alwaysKeepsRemoteCandidateRegardlessOfReachableSet() {
        let remoteConnectionID = UUID()
        let candidates = [candidate(remoteConnectionID, model: "claude-opus-4-8", tier: .premium)]

        let filtered = RouterOrdering.filterReachableCandidates(
            candidates, reachableLocalConnectionIDs: [],
            isLocalConnection: { _ in false })

        #expect(filtered.map(\.model) == ["claude-opus-4-8"])
    }

    @Test func mixedSetDropsOnlyTheUnreachableLocalOne() {
        let downLocalID = UUID()
        let upLocalID = UUID()
        let remoteID = UUID()
        let candidates = [
            candidate(downLocalID, model: "llama3.2", tier: .local),
            candidate(upLocalID, model: "qwen2.5-coder", tier: .local),
            candidate(remoteID, model: "claude-opus-4-8", tier: .premium),
        ]
        let localIDs: Set<UUID> = [downLocalID, upLocalID]

        let filtered = RouterOrdering.filterReachableCandidates(
            candidates, reachableLocalConnectionIDs: [upLocalID],
            isLocalConnection: { localIDs.contains($0) })

        #expect(Set(filtered.map(\.model)) == ["qwen2.5-coder", "claude-opus-4-8"])
    }

    // MARK: - LocalModelAvailability.refresh (async cache)

    @Test func refreshMarksReachableSetEmptyWhenLocalServerIsDown() async {
        let catalog = ModelCatalogService(http: ThrowingDataHTTPClient())
        let probe = LocalModelProbe(catalog: catalog)
        let connection = Connection(
            id: UUID(), presetID: "ollama", kind: .openAICompatible,
            displayName: "Ollama", baseURL: "http://localhost:11434", createdAt: Date())
        let availability = LocalModelAvailability()

        await availability.refresh(connections: [connection], probe: probe, tokenFor: { _ in nil })

        #expect(availability.reachableConnectionIDs.isEmpty)
    }

    @Test func refreshMarksReachableSetContainingConnectionWhenLocalServerIsUp() async {
        let body = #"{"data":[{"id":"llama3.2"}]}"#.data(using: .utf8)!
        let catalog = ModelCatalogService(http: StubDataHTTPClient(status: 200, body: body))
        let probe = LocalModelProbe(catalog: catalog)
        let connection = Connection(
            id: UUID(), presetID: "ollama", kind: .openAICompatible,
            displayName: "Ollama", baseURL: "http://localhost:11434", createdAt: Date())
        let availability = LocalModelAvailability()

        await availability.refresh(connections: [connection], probe: probe, tokenFor: { _ in nil })

        #expect(availability.reachableConnectionIDs == [connection.id])
    }

    @Test func refreshIgnoresNonLocalConnectionsEntirely() async {
        // A remote connection that would fail if probed (no /models mock matching
        // its shape) must never even be probed — `refresh` only iterates locals.
        let catalog = ModelCatalogService(http: ThrowingDataHTTPClient())
        let probe = LocalModelProbe(catalog: catalog)
        let remote = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com/v1", createdAt: Date())
        let availability = LocalModelAvailability()

        await availability.refresh(connections: [remote], probe: probe, tokenFor: { _ in nil })

        #expect(availability.reachableConnectionIDs.isEmpty)
    }
}
