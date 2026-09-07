import Testing
import Foundation
@testable import Ainkrad

@Suite("Revealing a notification's source")
struct SignalRevealTests {
    private let activeID = UUID()
    private let otherID = UUID()

    private func workspace(_ id: UUID, _ panes: [(String, UUID)]) -> SignalRevealWorkspace {
        SignalRevealWorkspace(id: id, panes: panes.map {
            SignalRevealWorkspace.Pane(appID: $0.0, blockID: $0.1)
        })
    }

    @Test("an open pane in the active workspace is focused, not duplicated")
    func focusesExistingPane() {
        let block = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("rune", block)])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: activeID, blockID: block),
                "opening a second empty terminal takes the user further from the session")
    }

    @Test("a pane on another workspace is focused there")
    func focusesAcrossWorkspaces() {
        let block = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("lore", UUID())]),
                         workspace(otherID, [("rune", block)])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: otherID, blockID: block))
    }

    @Test("the active workspace wins when the app is open in both")
    func prefersTheActiveWorkspace() {
        let here = UUID()
        let there = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("rune", here)]),
                         workspace(otherID, [("rune", there)])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: activeID, blockID: here),
                "yanking the user to another workspace is a bigger disruption than the ping")
    }

    @Test("an app that is not open anywhere opens")
    func opensWhenAbsent() {
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("lore", UUID())])],
            activeWorkspaceID: activeID)
        #expect(action == .openNewPane)
    }

    @Test("an overlay app is presented, never tiled")
    func overlayAppsArePresented() {
        let action = SignalReveal.action(
            appID: "hoard", presentsAsOverlay: true,
            workspaces: [workspace(activeID, [])],
            activeWorkspaceID: activeID)
        #expect(action == .presentOverlay)
    }

    @Test("the first matching pane wins when one app has several")
    func firstPaneWins() {
        let first = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("rune", first), ("rune", UUID())])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: activeID, blockID: first))
    }
    // MARK: - Payload delivery

    @Test("focusing an existing pane does NOT deliver the payload")
    func focusWithholdsPayload() {
        // The hub holds one pending payload per app and only a NEW pane pulls
        // it. Enqueuing here left it for the next unrelated pane to collect and
        // clobbered any legitimate pending launch in the meantime.
        let action = SignalRevealAction.focus(workspaceID: activeID, blockID: UUID())
        #expect(action.deliversPayload == false)
    }

    @Test("opening a new pane delivers the payload")
    func openDeliversPayload() {
        #expect(SignalRevealAction.openNewPane.deliversPayload)
    }

    @Test("presenting an overlay delivers the payload")
    func overlayDeliversPayload() {
        #expect(SignalRevealAction.presentOverlay.deliversPayload)
    }
    // MARK: - Locator matching (generation 10)

    private func workspace(_ id: UUID, panes: [(String, UUID, String?)]) -> SignalRevealWorkspace {
        SignalRevealWorkspace(id: id, panes: panes.map {
            SignalRevealWorkspace.Pane(appID: $0.0, blockID: $0.1, locator: $0.2)
        })
    }

    @Test("a locator picks the pane holding that session, not the first pane")
    func locatorPicksTheRightPane() {
        // The whole point: three Rune panes, and the notification came from
        // the third. Without a locator this focuses the first and looks like
        // it worked.
        let first = UUID(), second = UUID(), third = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, panes: [
                ("rune", first, "session-a"),
                ("rune", second, "session-b"),
                ("rune", third, "session-c"),
            ])],
            activeWorkspaceID: activeID,
            locator: "session-c")
        #expect(action == .focus(workspaceID: activeID, blockID: third))
    }

    @Test("an unmatched locator falls back to the app, never to nowhere")
    func unmatchedLocatorFallsBack() {
        // The pane that held the session has closed. Being taken to the app is
        // a good outcome; being taken nowhere is not.
        let only = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, panes: [("rune", only, "session-a")])],
            activeWorkspaceID: activeID,
            locator: "session-gone")
        #expect(action == .focus(workspaceID: activeID, blockID: only))
    }

    @Test("a nil or empty locator behaves exactly as generation 9 did")
    func noLocatorIsUnchanged() {
        let first = UUID()
        let panes = [("rune", first, Optional("session-a")), ("rune", UUID(), Optional("session-b"))]
        for locator in [nil, ""] as [String?] {
            let action = SignalReveal.action(
                appID: "rune", presentsAsOverlay: false,
                workspaces: [workspace(activeID, panes: panes)],
                activeWorkspaceID: activeID,
                locator: locator)
            #expect(action == .focus(workspaceID: activeID, blockID: first))
        }
    }

    @Test("a locator match on another workspace beats a bare app match here")
    func locatorMatchBeatsLocalAppMatch() {
        // A locator says one specific pane is the right answer, so it outranks
        // the usual preference for not switching workspaces.
        let localPane = UUID(), remotePane = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [
                workspace(activeID, panes: [("rune", localPane, "session-a")]),
                workspace(otherID, panes: [("rune", remotePane, "session-b")]),
            ],
            activeWorkspaceID: activeID,
            locator: "session-b")
        #expect(action == .focus(workspaceID: otherID, blockID: remotePane))
    }

    @Test("a locator belonging to a DIFFERENT app is not matched")
    func locatorIsScopedToItsApp() {
        // Locators are app-chosen strings, so two apps can use the same one by
        // coincidence. The appID check must come first.
        let lorePane = UUID(), runePane = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, panes: [
                ("lore", lorePane, "doc-1"),
                ("rune", runePane, "session-a"),
            ])],
            activeWorkspaceID: activeID,
            locator: "doc-1")
        #expect(action == .focus(workspaceID: activeID, blockID: runePane))
    }
}
