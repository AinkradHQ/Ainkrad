import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("AgentContextRegistryHub")
struct AgentContextRegistryHubTests {
    @Test("aggregates snapshots from multiple apps via per-app adapters")
    func aggregates() {
        let hub = AgentContextRegistryHub()
        let a = HostContextRegistry(appID: "terminal", hub: hub)
        let b = HostContextRegistry(appID: "gitmage", hub: hub)
        _ = a.register { AgentContextSnapshot(kind: "terminal", title: "T", text: "buf") }
        _ = b.register { AgentContextSnapshot(kind: "git", title: "G", text: "clean") }
        let sorted = hub.allSnapshots().sorted { $0.kind < $1.kind }
        #expect(sorted.map(\.kind) == ["git", "terminal"])
        #expect(sorted.map(\.title) == ["G", "T"])
        #expect(sorted.map(\.text) == ["clean", "buf"])
    }

    @Test("remove drops a source")
    func remove() {
        let hub = AgentContextRegistryHub()
        let a = HostContextRegistry(appID: "terminal", hub: hub)
        let token = a.register { AgentContextSnapshot(kind: "terminal", title: "T", text: "buf") }
        a.remove(token)
        #expect(hub.allSnapshots().isEmpty)
    }

    @Test("nil-returning sources are skipped")
    func skipsNil() {
        let hub = AgentContextRegistryHub()
        let a = HostContextRegistry(appID: "terminal", hub: hub)
        _ = a.register { nil }
        #expect(hub.allSnapshots().isEmpty)
    }
}
