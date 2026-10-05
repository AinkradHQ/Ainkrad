import CoreGraphics
import Testing

@testable import Ainkrad

/// The Workspace Overview panel hugs its content, which only works while every
/// region inside it can state a definite height. These are those statements —
/// a `ScrollView` left to itself claims every point offered, so if one of these
/// heights drifts away from the rows it is describing, the panel silently goes
/// back to being a fixed slab (too tall) or starts clipping (too short).
@Suite("Workspace Overview panel height")
struct WorkspaceOverviewLayoutTests {

    // MARK: - App grid

    @Test("an empty app grid asks for nothing beyond its padding")
    func emptyGridIsMinimal() {
        #expect(WorkspaceOverviewView.appGridHeight(count: 0) == 16)
    }

    @Test("the grid is three across, so one to three panes occupy exactly one row")
    func oneRowUpToThree() {
        let oneRow = WorkspaceOverviewView.appGridHeight(count: 1)
        #expect(WorkspaceOverviewView.appGridHeight(count: 2) == oneRow)
        #expect(WorkspaceOverviewView.appGridHeight(count: 3) == oneRow)
        #expect(WorkspaceOverviewView.appGridHeight(count: 4) > oneRow)
    }

    @Test("height grows one row at a time, never per pane")
    func growsByRows() {
        let rowOne = WorkspaceOverviewView.appGridHeight(count: 3)
        let rowTwo = WorkspaceOverviewView.appGridHeight(count: 6)
        let rowThree = WorkspaceOverviewView.appGridHeight(count: 9)
        #expect(rowTwo - rowOne == rowThree - rowTwo)
    }

    @Test("a workspace with many panes is capped, so the grid scrolls instead of pushing the preview off the panel")
    func manyPanesAreCapped() {
        let capped = WorkspaceOverviewView.appGridHeight(count: 200)
        #expect(capped == 262)
        #expect(WorkspaceOverviewView.appGridHeight(count: 40) <= 262)
    }

    @Test("height never decreases as panes are added")
    func monotonic() {
        var previous: CGFloat = 0
        for count in 0...30 {
            let height = WorkspaceOverviewView.appGridHeight(count: count)
            #expect(height >= previous)
            previous = height
        }
    }

    /// The panel's ceiling has to clear the content on a large window, or the
    /// panel overflows its chrome instead of scrolling inside it.
    @Test("the detail column fits under the panel's maximum")
    func contentFitsUnderCeiling() {
        let panel = WorkspaceOverviewView.panelChromeHeight + WorkspaceOverviewView.detailHeight
        #expect(panel <= WorkspaceOverviewView.maximumPanelHeight)
    }

    // MARK: - Ceiling

    @Test("the ceiling tracks the window but never exceeds the panel's maximum")
    func ceilingTracksWindow() {
        #expect(
            WorkspaceOverviewView.ceiling(forWindowHeight: 2000)
                == WorkspaceOverviewView.maximumPanelHeight)
        let mid = WorkspaceOverviewView.ceiling(forWindowHeight: 800)
        #expect(mid > 420)
        #expect(mid < WorkspaceOverviewView.maximumPanelHeight)
    }

    /// The first attempt at hugging used `fixedSize`, which refuses to shrink —
    /// so on a window shorter than the content the panel overflowed instead of
    /// adapting. The ceiling has to win in that direction.
    @Test("a short window clamps the panel rather than letting it overflow")
    func shortWindowClampsRatherThanOverflows() {
        let tiny = WorkspaceOverviewView.ceiling(forWindowHeight: 300)
        #expect(tiny == 420)

        let content =
            WorkspaceOverviewView.panelChromeHeight
            + WorkspaceOverviewView.detailHeight
        #expect(min(content, tiny) == tiny)
    }

    // MARK: - A constant height

    /// The panel must not resize as the selection moves down the list. Every
    /// state is fitted into one height instead of each being individually
    /// tight — so these assert SAMENESS, where an earlier version asserted that
    /// an empty workspace was shorter.
    @Test("an empty workspace occupies exactly the same column height as a filled one")
    func emptyAndFilledAreTheSameHeight() {
        let empty =
            WorkspaceOverviewView.detailHeaderHeight
            + WorkspaceOverviewView.emptyWorkspaceHeight + 16
        #expect(empty == WorkspaceOverviewView.detailHeight)
    }

    @Test("no pane count changes the column height")
    func paneCountNeverChangesHeight() {
        for count in [1, 2, 3, 4, 6, 9, 12, 40, 200] {
            let column =
                WorkspaceOverviewView.detailHeaderHeight
                + WorkspaceOverviewView.previewBottomPadding
                + WorkspaceOverviewView.previewHeight(forAppCount: count)
                + WorkspaceOverviewView.appSectionHeaderHeight
                + WorkspaceOverviewView.appGridHeight(count: count)
            #expect(
                column == WorkspaceOverviewView.detailHeight,
                "\(count) panes changed the column height")
        }
    }

    @Test("having nothing selected doesn't resize the panel either")
    func noSelectionIsTheSameHeight() {
        #expect(WorkspaceOverviewView.noSelectionHeight == WorkspaceOverviewView.detailHeight)
    }

    /// A constant height only costs nothing because the slack goes somewhere
    /// useful: fewer panes buy a bigger preview.
    @Test("the preview absorbs the slack, and stays within its readable range")
    func previewAbsorbsTheSlack() {
        let few = WorkspaceOverviewView.previewHeight(forAppCount: 1)
        let many = WorkspaceOverviewView.previewHeight(forAppCount: 12)
        #expect(few > many)
        #expect(few == WorkspaceOverviewView.maximumPreviewHeight)

        for count in [1, 3, 6, 12, 40, 200] {
            let height = WorkspaceOverviewView.previewHeight(forAppCount: count)
            #expect(height >= WorkspaceOverviewView.minimumPreviewHeight)
            #expect(height <= WorkspaceOverviewView.maximumPreviewHeight)
        }
    }

    /// If the grid ever grows enough that the preview would be squeezed below its
    /// floor, the column silently grows past `detailHeight` and the panel starts
    /// resizing again — so the floor has to be reachable but not breached.
    @Test("even the largest app grid leaves the preview above its floor")
    func largestGridStillClearsThePreviewFloor() {
        let fixed =
            WorkspaceOverviewView.detailHeaderHeight
            + WorkspaceOverviewView.previewBottomPadding
            + WorkspaceOverviewView.appSectionHeaderHeight
            + WorkspaceOverviewView.appGridHeight(count: 200)
        #expect(
            WorkspaceOverviewView.detailHeight - fixed
                >= WorkspaceOverviewView.minimumPreviewHeight)
    }
}
