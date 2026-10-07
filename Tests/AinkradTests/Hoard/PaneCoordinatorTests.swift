import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("PaneCoordinator")
struct PaneCoordinatorTests {
    private func makeStore() -> HoardPaneStore {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/Users/test"))
        fs.add(directory: "/Users/test", children: ["a.txt"])
        return HoardPaneStore(fileSystem: fs, persistence: InMemoryPersistenceStore())
    }

    @Test("a lone pane has no other pane, so the caller must prompt")
    func singlePane() {
        let coordinator = PaneCoordinator()
        let token = coordinator.register(makeStore())
        #expect(coordinator.paneCount == 1)
        #expect(coordinator.otherPane(than: token) == nil)
    }

    @Test("with exactly two panes, the other one is unambiguous")
    func twoPanes() {
        let coordinator = PaneCoordinator()
        let first = coordinator.register(makeStore())
        let secondStore = makeStore()
        let second = coordinator.register(secondStore)

        #expect(coordinator.otherPane(than: first) === secondStore)
        #expect(coordinator.otherPane(than: second) !== secondStore)
    }

    @Test("with three panes, the most-recently-focused other pane wins")
    func threePanes() {
        let coordinator = PaneCoordinator()
        let first = coordinator.register(makeStore())
        let secondStore = makeStore()
        _ = coordinator.register(secondStore)
        let thirdStore = makeStore()
        let third = coordinator.register(thirdStore)

        coordinator.noteFocus(third)
        // Focusing the CALLER must not make it its own target.
        coordinator.noteFocus(first)
        #expect(coordinator.otherPane(than: first) === thirdStore)
    }

    @Test("deregistering removes a pane from consideration")
    func deregister() {
        let coordinator = PaneCoordinator()
        let first = coordinator.register(makeStore())
        let secondStore = makeStore()
        let second = coordinator.register(secondStore)

        coordinator.deregister(second)
        #expect(coordinator.paneCount == 1)
        #expect(coordinator.otherPane(than: first) == nil)
    }

    // The reason this type lives in `AppEnvironment` rather than inside a
    // pane: host tiling destroys panes, and the pane you were copying FROM
    // going away must not break the survivor.
    @Test("closing the pane you copied from leaves the survivor intact")
    func survivorUnaffected() {
        let coordinator = PaneCoordinator()
        let sourceToken = coordinator.register(makeStore())
        let survivorStore = makeStore()
        let survivor = coordinator.register(survivorStore)

        coordinator.deregister(sourceToken)
        #expect(coordinator.paneCount == 1)
        #expect(coordinator.otherPane(than: survivor) == nil)

        let newStore = makeStore()
        _ = coordinator.register(newStore)
        #expect(coordinator.otherPane(than: survivor) === newStore)
    }

    @Test("focus notes for unknown tokens are ignored")
    func unknownFocusIgnored() {
        let coordinator = PaneCoordinator()
        let token = coordinator.register(makeStore())
        coordinator.noteFocus(UUID())
        #expect(coordinator.paneCount == 1)
        #expect(coordinator.otherPane(than: token) == nil)
    }

    @Test("registering the same store twice yields distinct panes")
    func distinctTokens() {
        let coordinator = PaneCoordinator()
        let store = makeStore()
        let first = coordinator.register(store)
        let second = coordinator.register(store)
        #expect(first != second)
        #expect(coordinator.paneCount == 2)
    }
}
