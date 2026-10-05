import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import AinkradDevHost

/// Regression cover for the Dev Host crashing on any plugin that publishes
/// agent context.
///
/// `HostContextRegistry`, `HostActionRegistry` and `HostAppLauncher` each hold
/// their hub `unowned` — safe in the real host, where `AppEnvironment` owns
/// them for the process lifetime. `makeHostServices` used to construct all
/// three INLINE, so every hub was deallocated the moment it returned and the
/// first `host.context.register(...)` aborted in `swift_unownedRetainStrong`.
///
/// The Dev Host exists to prove a plugin loads. It was aborting on load for
/// any plugin using a first-class SDK feature, and nothing caught it because
/// this test target was not wired into `make test`.
@Suite("Dev Host host services")
@MainActor
struct DevHostHostServicesTests {
    @Test("a plugin can publish agent context through the services it is handed")
    func contextRegistrationSurvivesTheFactory() {
        let host = DevHostModel.makeHostServices(appID: "probe", presentation: .pane)

        // Before the fix this line aborted the process rather than failing.
        let token = host.context.register {
            AgentContextSnapshot(kind: "probe", title: "T", text: "X")
        }

        let snapshots = DevHostModel.contextHub.allSnapshots()
        #expect(snapshots.contains { $0.kind == "probe" })

        host.context.remove(token)
        #expect(!DevHostModel.contextHub.allSnapshots().contains { $0.kind == "probe" })
    }

    @Test("every plugin is handed the same shared hubs")
    func hubsAreShared() {
        // Two apps must reach ONE hub, or context published by one plugin is
        // invisible to the host and to every other plugin.
        let first = DevHostModel.makeHostServices(appID: "a", presentation: .pane)
        let second = DevHostModel.makeHostServices(appID: "b", presentation: .pane)

        let t1 = first.context.register { AgentContextSnapshot(kind: "a", title: "A", text: "A") }
        let t2 = second.context.register { AgentContextSnapshot(kind: "b", title: "B", text: "B") }

        let kinds = Set(DevHostModel.contextHub.allSnapshots().map(\.kind))
        #expect(kinds.isSuperset(of: ["a", "b"]))

        first.context.remove(t1)
        second.context.remove(t2)
    }
}
