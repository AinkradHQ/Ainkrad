import AinkradHostRuntime
import AppKit
import Testing

@testable import Ainkrad

/// Captures `reply(_:)` calls instead of touching a real `NSApplication`, so
/// `QuitCoordinator` is fully testable in-process.
final class FakeTerminationReplier: TerminationReplying {
    private(set) var replies: [Bool] = []

    func reply(_ shouldTerminate: Bool) {
        replies.append(shouldTerminate)
    }
}

@Suite("QuitCoordinator")
@MainActor
final class QuitCoordinatorTests {
    @Test("requestTerminate returns .terminateNow and doesn't confirm when confirmBeforeQuit is false")
    func requestTerminateSkipsConfirmationWhenDisabled() {
        let persistence = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.confirmBeforeQuit = false
        persistence.save(settings)
        let terminator = FakeTerminationReplier()
        let coordinator = QuitCoordinator(persistence: persistence, terminator: terminator)

        let reply = coordinator.requestTerminate()

        #expect(reply == .terminateNow)
        #expect(coordinator.isConfirming == false)
    }

    @Test("requestTerminate returns .terminateLater and starts confirming when confirmBeforeQuit is true (default)")
    func requestTerminateConfirmsByDefault() {
        let persistence = InMemoryPersistenceStore()
        let terminator = FakeTerminationReplier()
        let coordinator = QuitCoordinator(persistence: persistence, terminator: terminator)

        let reply = coordinator.requestTerminate()

        #expect(reply == .terminateLater)
        #expect(coordinator.isConfirming == true)
    }

    @Test("confirm(dontAskAgain: false) stops confirming, replies true, and leaves confirmBeforeQuit set")
    func confirmWithoutDontAskAgain() {
        let persistence = InMemoryPersistenceStore()
        let terminator = FakeTerminationReplier()
        let coordinator = QuitCoordinator(persistence: persistence, terminator: terminator)
        _ = coordinator.requestTerminate()

        coordinator.confirm(dontAskAgain: false)

        #expect(coordinator.isConfirming == false)
        #expect(terminator.replies == [true])
        #expect((persistence.load(GlobalSettings.self) ?? GlobalSettings()).confirmBeforeQuit == true)
    }

    @Test("confirm(dontAskAgain: true) persists confirmBeforeQuit = false, preserving other fields, and replies true")
    func confirmWithDontAskAgainPersistsPreference() {
        let persistence = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.colorSchemeDark = "cyberPurple"
        persistence.save(settings)
        let terminator = FakeTerminationReplier()
        let coordinator = QuitCoordinator(persistence: persistence, terminator: terminator)
        _ = coordinator.requestTerminate()

        coordinator.confirm(dontAskAgain: true)

        let saved = persistence.load(GlobalSettings.self)
        #expect(saved?.confirmBeforeQuit == false)
        #expect(saved?.colorSchemeDark == "cyberPurple")
        #expect(terminator.replies == [true])
    }

    @Test("cancel stops confirming and replies false")
    func cancelStopsConfirmingAndRepliesFalse() {
        let persistence = InMemoryPersistenceStore()
        let terminator = FakeTerminationReplier()
        let coordinator = QuitCoordinator(persistence: persistence, terminator: terminator)
        _ = coordinator.requestTerminate()

        coordinator.cancel()

        #expect(coordinator.isConfirming == false)
        #expect(terminator.replies == [false])
    }
}
