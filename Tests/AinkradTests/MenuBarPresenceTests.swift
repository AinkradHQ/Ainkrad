import Foundation
import Testing

@testable import Ainkrad

@Suite("MenuBarPresence")
@MainActor
struct MenuBarPresenceTests {
    private final class StubRunSource: MenuBarRunSource {
        var activeRunItems: [MenuBarRunItem] = []
        private(set) var stopped: [UUID] = []
        func stopRun(_ id: UUID) { stopped.append(id) }
    }

    @Test func toggleFlipsPopoverState() {
        let p = MenuBarPresence(runs: EmptyMenuBarRunSource())
        #expect(p.isPopoverOpen == false)
        p.toggle()
        #expect(p.isPopoverOpen == true)
        p.toggle()
        #expect(p.isPopoverOpen == false)
    }

    @Test func summaryWhenNoRuns() {
        let p = MenuBarPresence(runs: EmptyMenuBarRunSource())
        #expect(p.runSummary == "No active runs")
        #expect(p.runItems.isEmpty)
    }

    @Test func summaryCountsActiveRuns() {
        let src = StubRunSource()
        src.activeRunItems = [
            MenuBarRunItem(id: UUID(), title: "build feature", isActive: true),
            MenuBarRunItem(id: UUID(), title: "nightly", isActive: true),
        ]
        let p = MenuBarPresence(runs: src)
        #expect(p.runItems.count == 2)
        #expect(p.runSummary == "2 running")
    }

    @Test func stopForwardsToSource() {
        let src = StubRunSource()
        let id = UUID()
        src.activeRunItems = [MenuBarRunItem(id: id, title: "x", isActive: true)]
        let p = MenuBarPresence(runs: src)
        p.stop(id)
        #expect(src.stopped == [id])
    }
}
