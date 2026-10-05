import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup coordinator")
@MainActor
struct SetupCoordinatorTests {
    @Test func afreshInstallOwesEveryStep() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        #expect(c.steps == SetupStep.allCases)
        #expect(c.step == .welcome)
        #expect(!c.isComplete)
    }

    @Test func advancingWalksTheStepsInOrderAndStops() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        for _ in 0..<20 { c.advance() }
        #expect(c.step == .done, "advance past the end must clamp, not wrap or crash")
    }

    @Test func completingWritesTheMarkerWithTheCurrentVersion() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.complete()
        let doc = store.load(SetupDocument.self)
        #expect(doc?.completedAt != nil)
        #expect(doc?.setupVersion == SetupCoordinator.currentSetupVersion)
        #expect(c.isComplete)
    }

    /// A user who completed an older setup owes only the steps added since —
    /// not the whole wizard again.
    @Test func anOlderCompletionOwesOnlyTheNewSteps() {
        let store = InMemoryPersistenceStore()
        store.save(SetupDocument(completedAt: Date(timeIntervalSince1970: 0), setupVersion: 0))
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(c.steps.allSatisfy { $0.introducedIn > 0 || $0 == .done })
        #expect(!c.steps.contains(.home), "a configured user must not be asked for a vault again")
    }

    @Test func aCurrentCompletionOwesNothing() {
        let store = InMemoryPersistenceStore()
        store.save(
            SetupDocument(
                completedAt: Date(),
                setupVersion: SetupCoordinator.currentSetupVersion))
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(c.isComplete)
    }

    /// REVERSED, deliberately. This test previously asserted that adopting a
    /// vault removed `.home` immediately, so Back could never return to it.
    /// Hand-testing rejected that: the step vanished mid-wizard and the folder —
    /// the one decision that determines where all of the user's work lives —
    /// became unchangeable before setup had even finished.
    ///
    /// The rule is now: `.home` stays reachable until setup COMPLETES in that
    /// vault. `theCompletedCoordinatorHasNoHomeStepAtAll` pins the other half.
    @Test func backReachesTheHomeStepWhileSetupIsUnfinished() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        for _ in 0..<20 { c.advance() }
        for _ in 0..<20 { c.back() }
        #expect(
            c.steps.contains(.home),
            "setup is unfinished, so the folder must still be changeable")
        #expect(c.step == c.steps.first)
    }

    /// Back is offered on every step but the first shown — and on the first it
    /// is absent, not disabled, which is what `canGoBack` drives in the views.
    @Test func backIsUnavailableOnlyOnTheFirstStep() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        #expect(c.step == .welcome)
        #expect(!c.canGoBack)
        for _ in 0..<20 {
            c.advance()
            #expect(c.canGoBack, "every step after the first must offer Back")
        }
        #expect(c.step == .done)
    }

    /// A provisional (never-adopted) home is the one case where `.home` is in
    /// `steps` at all — and even there Back may only reach it because nothing
    /// has been adopted yet. Once adoption happens the coordinator is rebuilt
    /// with `isProvisionalHome: false` (see `SetupOverlayView.reseat`), and
    /// that rebuilt list is what `backReachesTheHomeStepWhileSetupIsUnfinished`
    /// pins.
    ///
    /// The discriminator is the MARKER, not the flag passed in: a vault whose
    /// setup already completed is a settled home and is never re-asked, while a
    /// vault adopted moments ago mid-wizard still is. Both cases arrive here as
    /// `isProvisionalHome: false`, so a caller cannot get this wrong by passing
    /// the flag differently.
    @Test func theCompletedCoordinatorHasNoHomeStepAtAll() {
        let store = InMemoryPersistenceStore()
        var doc = SetupDocument()
        doc.completedAt = Date()
        doc.setupVersion = SetupCoordinator.currentSetupVersion
        store.save(doc)

        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(
            !c.steps.contains(.home),
            "a vault whose setup is finished must never be re-asked for its folder")
    }

    /// The mid-wizard case, stated directly: a vault has been adopted (so the
    /// home is no longer provisional) but nothing has completed in it yet.
    @Test func aFreshlyAdoptedVaultKeepsTheHomeStep() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(c.steps.contains(.home))
        #expect(
            c.steps == SetupStep.allCases,
            "an unfinished setup owes every step, whatever the home's state")
    }
}
