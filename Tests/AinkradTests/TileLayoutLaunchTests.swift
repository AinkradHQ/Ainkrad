import AinkradAppKit
import Testing

@testable import Ainkrad

@Suite("TileLayout document launches")
struct TileLayoutLaunchTests {
    @Test("a document goes to the open pane of its app")
    func documentReusesOpenPane() {
        let layout = TileLayout()
        _ = layout.openApp("lore")
        let second = layout.openApp("lore")
        _ = layout.openApp("rune")
        let intent = AinkradLaunchIntent(path: "/v/note.md")
        #expect(layout.paneForDocument(appID: "lore", intent: intent)?.id == second.id)
    }

    @Test("no open pane, or not a document, opens a new one")
    func otherLaunchesDoNotReuse() {
        let layout = TileLayout()
        _ = layout.openApp("rune")
        #expect(layout.paneForDocument(appID: "lore", intent: AinkradLaunchIntent(path: "/v/n.md")) == nil)
        let ssh = AinkradLaunchIntent(kind: "ssh", path: "host")
        #expect(layout.paneForDocument(appID: "rune", intent: ssh) == nil)
        #expect(layout.paneForDocument(appID: "rune", intent: nil) == nil)
    }
}
