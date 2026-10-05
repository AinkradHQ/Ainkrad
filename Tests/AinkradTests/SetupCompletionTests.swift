import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup completion")
@MainActor
struct SetupCompletionTests {
    @Test func aConfiguredVaultWithNoMarkerReRaisesTheGate() {
        let t = TestHome.make("complete")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        // Real vault, but setup never finished.
        #expect(
            SetupCoordinator(
                persistence: env.persistence,
                isProvisionalHome: false
            ).isComplete == false)
    }

    @Test func completingClearsTheGateAndSurvivesARebootstrap() {
        let t = TestHome.make("complete2")
        defer { t.cleanup() }

        let first = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        SetupCoordinator(persistence: first.persistence, isProvisionalHome: true).complete()

        let second = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        #expect(
            SetupCoordinator(
                persistence: second.persistence,
                isProvisionalHome: false
            ).isComplete)
    }

    /// The marker lives in the vault, so a user who moves their vault to a new Mac
    /// is not asked to set up again.
    @Test func theMarkerLivesInTheVault() {
        let t = TestHome.make("complete3")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        SetupCoordinator(persistence: env.persistence, isProvisionalHome: true).complete()

        #expect(
            FileManager.default.fileExists(
                atPath: t.home.shared(.config).appendingPathComponent("setup.json").path))
    }

    /// The launch-time gate: no Home yet, or a Home whose setup never finished
    /// (force-quit mid-wizard) / owes steps from a newer setupVersion.
    @Test func theLaunchGateRisesForAProvisionalHomeOrAnIncompleteMarker() {
        #expect(SetupGate.raisedAtLaunch(provisionalHome: true, setupIsComplete: false))
        #expect(SetupGate.raisedAtLaunch(provisionalHome: false, setupIsComplete: false))
        #expect(!SetupGate.raisedAtLaunch(provisionalHome: false, setupIsComplete: true))
    }

    /// The launch check and the wizard's mid-session lowering must agree: what
    /// the Done step writes is exactly what keeps the gate down next launch.
    @Test func completingInTheWizardKeepsTheGateDownOnTheNextLaunch() {
        let t = TestHome.make("complete4")
        defer { t.cleanup() }

        let first = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        #expect(
            SetupGate.raisedAtLaunch(
                provisionalHome: false,
                setupIsComplete: SetupCoordinator(
                    persistence: first.persistence,
                    isProvisionalHome: false
                ).isComplete))

        SetupCoordinator(persistence: first.persistence, isProvisionalHome: false).complete()

        let second = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        #expect(
            !SetupGate.raisedAtLaunch(
                provisionalHome: false,
                setupIsComplete: SetupCoordinator(
                    persistence: second.persistence,
                    isProvisionalHome: false
                ).isComplete))
    }

    /// Back on the closing step must never be able to re-ask for a Home. After
    /// adoption the coordinator is rebuilt with `isProvisionalHome: false`,
    /// which drops `.home` from `steps` — so walking back cannot reach it.
    /// The re-raised gate: setup COMPLETED in this vault once, and the user is
    /// back only for a step they deferred. The folder is settled, so no amount
    /// of Back may offer to move it.
    ///
    /// Narrowed from "any non-provisional coordinator" when `.home` became
    /// reachable during an unfinished setup — see
    /// `SetupCoordinatorTests.backReachesTheHomeStepWhileSetupIsUnfinished`.
    /// The completed marker is what makes this the settled case rather than the
    /// mid-wizard one.
    @Test func backFromDoneCannotReturnToTheHomeStepOnACompletedVault() {
        let store = InMemoryPersistenceStore()
        store.save(
            SetupDocument(
                completedAt: Date(),
                setupVersion: SetupCoordinator.currentSetupVersion,
                deferredSteps: [SetupStep.providers.rawValue]))
        let reseated = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(!reseated.steps.contains(.home))
        #expect(reseated.steps.count > 1, "otherwise Back has nowhere to go and this proves nothing")

        while reseated.canAdvance { reseated.advance() }
        #expect(reseated.step == .done)

        for _ in 0..<20 { reseated.back() }
        #expect(reseated.step != .home)
        #expect(reseated.step == reseated.steps.first)
    }
}
