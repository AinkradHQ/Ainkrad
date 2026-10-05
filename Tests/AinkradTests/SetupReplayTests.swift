import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("Setup replay")
@MainActor
struct SetupReplayTests {
    /// A store whose marker says setup finished at the current version with
    /// nothing owed — the state every existing user is in.
    private func completedPersistence() -> InMemoryPersistenceStore {
        let store = InMemoryPersistenceStore()
        store.save(
            SetupDocument(
                completedAt: Date(timeIntervalSince1970: 0),
                setupVersion: SetupCoordinator.currentSetupVersion,
                deferredSteps: []))
        return store
    }

    /// The regression this guards: without replay, re-raising the gate on a
    /// completed vault shows the Ready screen and nothing else.
    @Test("a completed vault re-raises to Done alone without replay")
    func withoutReplay() {
        let coordinator = SetupCoordinator(
            persistence: completedPersistence(),
            isProvisionalHome: false)
        #expect(coordinator.steps == [.done])
    }

    @Test("replay walks every step")
    func replayWalksSteps() {
        let coordinator = SetupCoordinator(
            persistence: completedPersistence(),
            isProvisionalHome: false,
            isReplay: true)
        #expect(coordinator.steps.contains(.appearance))
        #expect(coordinator.steps.contains(.you))
        #expect(coordinator.steps.contains(.providers))
        #expect(coordinator.steps.contains(.done))
    }

    /// A vault that stands is not re-offered for relocation — the same rule the
    /// re-raised gate already follows, and the reason Settings shows Home
    /// read-only.
    @Test("replay never re-asks for the Home folder")
    func replaySkipsHome() {
        let coordinator = SetupCoordinator(
            persistence: completedPersistence(),
            isProvisionalHome: false,
            isReplay: true)
        #expect(!coordinator.steps.contains(.home))
    }

    @Test("replay starts at the first step, not at Done")
    func replayStartsAtFirstStep() {
        let coordinator = SetupCoordinator(
            persistence: completedPersistence(),
            isProvisionalHome: false,
            isReplay: true)
        #expect(coordinator.step == .welcome)
    }
}
