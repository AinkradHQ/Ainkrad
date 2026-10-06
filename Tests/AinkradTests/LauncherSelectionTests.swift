import AinkradAppKit
import Testing

@testable import Ainkrad

@Suite("Launcher selection")
struct LauncherSelectionTests {
    @Test func listUpAndDownStepOneRow() {
        #expect(launcherArrowStep(.down, isGrid: false, columns: 4) == 1)
        #expect(launcherArrowStep(.up, isGrid: false, columns: 4) == -1)
    }

    @Test func listLeavesLeftAndRightToTheCaret() {
        #expect(launcherArrowStep(.left, isGrid: false, columns: 4) == nil)
        #expect(launcherArrowStep(.right, isGrid: false, columns: 4) == nil)
    }

    @Test func gridUpAndDownStepAWholeRow() {
        #expect(launcherArrowStep(.down, isGrid: true, columns: 4) == 4)
        #expect(launcherArrowStep(.up, isGrid: true, columns: 4) == -4)
    }

    @Test func gridLeftAndRightStepOneCell() {
        #expect(launcherArrowStep(.left, isGrid: true, columns: 4) == -1)
        #expect(launcherArrowStep(.right, isGrid: true, columns: 4) == 1)
    }

    @Test func selectionWrapsAtBothEnds() {
        #expect(launcherSelection(4, movedBy: 1, count: 5) == 0)
        #expect(launcherSelection(0, movedBy: -1, count: 5) == 4)
        #expect(launcherSelection(1, movedBy: 4, count: 6) == 5)
        #expect(launcherSelection(2, movedBy: -4, count: 6) == 4)
    }

    @Test func emptyResultsKeepTheSelection() {
        #expect(launcherSelection(0, movedBy: 1, count: 0) == 0)
    }
}
