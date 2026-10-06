import Foundation
import Testing

@testable import Ainkrad

/// The history sidebar overlays (rather than squeezes) the chat column when
/// the pane can't hold both.
@Suite struct SageSidebarLayoutTests {
    private let threshold = SageSidebarLayout.width + SageSidebarLayout.chatMinWidth

    @Test func narrowPaneOverlaysSidebar() {
        #expect(SageSidebarLayout.overlays(paneWidth: 500))
        #expect(SageSidebarLayout.overlays(paneWidth: threshold - 1))
    }

    @Test func widePaneKeepsSidebarInFlow() {
        #expect(!SageSidebarLayout.overlays(paneWidth: threshold))
        #expect(!SageSidebarLayout.overlays(paneWidth: 1200))
    }
}
