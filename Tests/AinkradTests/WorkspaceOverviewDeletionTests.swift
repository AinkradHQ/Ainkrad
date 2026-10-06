import Testing

@testable import Ainkrad

/// The delete confirmation's message, now handed to the kit's
/// `AinkradConfirmDialog` as a plain string rather than laid out by a local
/// view — pinned so the wording survives the swap.
@Suite("Workspace Overview deletion message")
struct WorkspaceOverviewDeletionTests {

    @Test("one app is singular: its session")
    func singular() {
        #expect(
            WorkspaceOverviewView.deletionMessage(appCount: 1)
                == "1 app still running here — its session will end.")
    }

    @Test("several apps are plural: their sessions")
    func plural() {
        #expect(
            WorkspaceOverviewView.deletionMessage(appCount: 3)
                == "3 apps still running here — their sessions will end.")
    }
}
