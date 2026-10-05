import Foundation
import Testing

@testable import Ainkrad

@Suite("Pane tab names")
@MainActor
struct PaneTitleTests {

    @Test("an unnamed pane falls back to the app's display name, a renamed one keeps its own")
    func fallbackAndOverride() {
        let block = Block(appID: "terminal")
        #expect(block.displayTitle(appName: "Rune") == "Rune")

        block.rename(to: "build")
        #expect(block.displayTitle(appName: "Rune") == "build")
    }

    @Test("with no app name at all the pane falls back to its app id, never to an empty label")
    func fallsBackToAppID() {
        #expect(Block(appID: "terminal").displayTitle(appName: nil) == "terminal")
    }

    @Test("renaming to blank clears the name so the pane follows the app again")
    func blankRenameClears() {
        let block = Block(appID: "terminal", title: "build")

        block.rename(to: "   ")
        #expect(block.title == nil)
        #expect(block.displayTitle(appName: "Rune") == "Rune")
    }

    @Test("a rename is trimmed")
    func renameTrims() {
        let block = Block(appID: "terminal")
        block.rename(to: "  deploy \n")
        #expect(block.title == "deploy")
    }

    @Test("renaming through the layout notifies persistence")
    func renameNotifiesPersistence() {
        let layout = TileLayout()
        let block = layout.openApp("terminal")
        var changes = 0
        layout.onStructuralChange = { changes += 1 }

        layout.rename(block.id, to: "logs")

        #expect(block.title == "logs")
        #expect(changes == 1)
    }

    @Test("renaming an unknown pane is a no-op, not a crash or a spurious save")
    func renameUnknownPaneIsIgnored() {
        let layout = TileLayout()
        _ = layout.openApp("terminal")
        var changes = 0
        layout.onStructuralChange = { changes += 1 }

        layout.rename(UUID(), to: "logs")

        #expect(changes == 0)
    }

    @Test("pane names survive a snapshot round-trip")
    func namesRoundTrip() throws {
        let layout = TileLayout()
        let a = layout.openApp("terminal")
        _ = layout.openApp("settings")
        layout.rename(a.id, to: "build")

        let snapshot = try #require(layout.snapshot())
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: try JSONEncoder().encode(snapshot))

        let restored = TileLayout()
        restored.apply(decoded)

        #expect(restored.blocks.map(\.title) == ["build", nil])
    }

    @Test("a layout written before renaming existed still decodes, with no names")
    func decodesLegacySnapshotWithoutTitles() throws {
        let json = Data(
            #"{"axis":"h","fractions":[0.5,0.5],"children":[{"appID":"terminal"},{"appID":"settings"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: json)

        let restored = TileLayout()
        restored.apply(decoded)

        #expect(restored.appIDs == ["terminal", "settings"])
        #expect(restored.blocks.allSatisfy { $0.title == nil })
    }

    @Test("splitting a renamed pane carries the name onto the new pane")
    func splitInheritsName() throws {
        let layout = TileLayout()
        let a = layout.openApp("terminal")
        layout.rename(a.id, to: "build")

        let b = try #require(layout.split(a.id, edge: .bottom))
        #expect(b.title == "build")
    }
}
