import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@Suite("Model discovery cache")
struct ModelDiscoveryCacheTests {
    let id = UUID()
    let ttl: TimeInterval = 300

    @Test("fetches when never fetched") func neverFetched() {
        #expect(shouldFetchModels(connectionID: id, now: Date(), lastFetch: [:], inFlight: [], ttl: ttl) == true)
    }
    @Test("skips when a fetch is already in flight") func inFlightSkips() {
        #expect(shouldFetchModels(connectionID: id, now: Date(), lastFetch: [:], inFlight: [id], ttl: ttl) == false)
    }
    @Test("skips when the cached entry is younger than the TTL") func freshSkips() {
        let now = Date()
        #expect(
            shouldFetchModels(
                connectionID: id, now: now, lastFetch: [id: now.addingTimeInterval(-60)], inFlight: [], ttl: ttl)
                == false)
    }
    @Test("fetches when the cached entry is older than the TTL") func staleFetches() {
        let now = Date()
        #expect(
            shouldFetchModels(
                connectionID: id, now: now, lastFetch: [id: now.addingTimeInterval(-600)], inFlight: [], ttl: ttl)
                == true)
    }
}

/// Locks in that the composer's Auto pill selection is a stable sentinel — it
/// resolves to `.auto` whenever the router is on and nothing is pinned, so the
/// trigger shows a steady "Auto" and never substitutes a mid-turn resolved
/// model (which would visibly jump on settle).
@Suite("Auto pill stability")
struct AutoPillStabilityTests {
    @Test("Auto selection is stable regardless of last-resolved model") func stable() {
        #expect(modelPillSelectionIsAuto(pinnedModel: nil, routerEnabled: true) == true)
        // A pin always wins over Auto (matches ModelRouter pin precedence).
        #expect(modelPillSelectionIsAuto(pinnedModel: "gpt-x", routerEnabled: true) == false)
        // Router off + no pin → not Auto (shows the standing default, also stable).
        #expect(modelPillSelectionIsAuto(pinnedModel: nil, routerEnabled: false) == false)
    }

    @Test("a pin is displayed verbatim and never overridden by the resolved model") func pinWins() {
        #expect(
            modelPillDisplayModel(
                pinnedModel: "claude-x", routerEnabled: true,
                lastResolvedModel: "gpt-y", standingDefault: "d") == "claude-x")
    }
}

/// Locks in the grouped/enriched/offline-aware picker's pure section builder:
/// Auto section first, one section per connection, offline LOCAL connections
/// disabled with a "server down" detail, curated models marked, cloud/local
/// icons chosen correctly, and the "Manage connections…" row stays reachable.
@Suite("Model picker grouped sections")
struct ModelPickerSectionsTests {
    let claudeConn = Connection(
        id: UUID(), presetID: "claude", kind: .claude,
        displayName: "Claude Cloud", baseURL: "https://api.anthropic.com/v1", createdAt: Date())
    let ollamaConn = Connection(
        id: UUID(), presetID: "ollama", kind: .openAICompatible,
        displayName: "Local Ollama", baseURL: "http://localhost:11434/v1", createdAt: Date())

    private func models(for c: Connection) -> [String] {
        c.presetID == "claude" ? ["claude-opus-4-8", "claude-haiku-4-8"] : ["llama3.2"]
    }
    private func curated(for c: Connection) -> [String] {
        c.presetID == "claude" ? ["claude-opus-4-8"] : []
    }
    private func isLocal(_ c: Connection) -> Bool { c.presetID == "ollama" }

    @Test("Auto section first, then one section per connection, then Manage")
    func sectionsShape() {
        let sections = modelPickerSections(
            connections: [claudeConn, ollamaConn], modelsFor: models,
            curatedFor: curated, isLocal: isLocal,
            reachable: [claudeConn.id, ollamaConn.id], activeConnectionID: claudeConn.id)
        #expect(sections.count == 4)
        #expect(sections[0].header == "Auto")
        #expect(sections[0].rows.first?.value == .auto)
        #expect(sections[1].header == "Claude Cloud")
        #expect(sections[1].rows.map(\.title) == ["claude-opus-4-8", "claude-haiku-4-8"])
        #expect(sections[2].header == "Local Ollama")
        #expect(sections[3].rows.first?.value == .manage)
    }

    @Test("offline local connection rows are disabled with a server-down detail")
    func offlineLocal() {
        let sections = modelPickerSections(
            connections: [ollamaConn], modelsFor: models,
            curatedFor: curated, isLocal: isLocal,
            reachable: [], activeConnectionID: nil)
        let rows = sections.first(where: { $0.header == "Local Ollama" })!.rows
        #expect(rows.allSatisfy { $0.isEnabled == false })
        #expect(rows.allSatisfy { $0.detail == "server down" })
    }

    @Test("a reachable local connection's rows stay enabled")
    func reachableLocal() {
        let sections = modelPickerSections(
            connections: [ollamaConn], modelsFor: models,
            curatedFor: curated, isLocal: isLocal,
            reachable: [ollamaConn.id], activeConnectionID: nil)
        let rows = sections.first(where: { $0.header == "Local Ollama" })!.rows
        #expect(rows.allSatisfy { $0.isEnabled == true })
    }

    @Test("curated model gets a checkmark marker in its detail, others don't")
    func curatedMarker() {
        let sections = modelPickerSections(
            connections: [claudeConn], modelsFor: models,
            curatedFor: curated, isLocal: isLocal,
            reachable: [claudeConn.id], activeConnectionID: nil)
        let rows = sections.first(where: { $0.header == "Claude Cloud" })!.rows
        let curatedRow = rows.first(where: { $0.title == "claude-opus-4-8" })!
        #expect(curatedRow.detail?.contains("✓") == true)
        let plainRow = rows.first(where: { $0.title == "claude-haiku-4-8" })!
        #expect(plainRow.detail?.contains("✓") == false)
    }

    @Test("cloud vs local icon is chosen correctly")
    func icons() {
        let sections = modelPickerSections(
            connections: [claudeConn, ollamaConn], modelsFor: models,
            curatedFor: curated, isLocal: isLocal,
            reachable: [claudeConn.id, ollamaConn.id], activeConnectionID: nil)
        let cloudRow = sections.first(where: { $0.header == "Claude Cloud" })!.rows.first!
        let localRow = sections.first(where: { $0.header == "Local Ollama" })!.rows.first!
        #expect(cloudRow.icon == "icloud")
        #expect(localRow.icon == "desktopcomputer")
    }

    @Test("Manage connections stays reachable as a trailing row")
    func manageRow() {
        let sections = modelPickerSections(
            connections: [claudeConn], modelsFor: models,
            curatedFor: curated, isLocal: isLocal,
            reachable: [claudeConn.id], activeConnectionID: nil)
        #expect(sections.last?.rows.first?.value == .manage)
        #expect(sections.last?.rows.first?.isEnabled == true)
    }
}
