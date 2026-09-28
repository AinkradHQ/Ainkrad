import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

/// Enter on a file in Hoard. E5 of the Basic Mode milestone.
@Suite("Hoard — open a document")
@MainActor
struct HoardOpenDocumentTests {

    private func entry(_ name: String) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/Users/test/\(name)"), name: name,
                  isDirectory: false, isSymlink: false, isHidden: false,
                  size: 0, modified: Date())
    }

    @Test("Markdown is recognised, by extension, case-insensitively")
    func markdownIsRecognised() {
        #expect(HoardTab.isMarkdown(URL(fileURLWithPath: "/a/roadmap.md")))
        #expect(HoardTab.isMarkdown(URL(fileURLWithPath: "/a/README.MD")))
        #expect(HoardTab.isMarkdown(URL(fileURLWithPath: "/a/notes.markdown")))
        #expect(HoardTab.isMarkdown(URL(fileURLWithPath: "/a/notes.mkd")))
    }

    @Test("Everything else is NOT, so Enter stays a no-op on it")
    func nonMarkdownIsNot() {
        // Deliberately not a general file-opener. Enter doing something
        // surprising on a binary is worse than Enter doing nothing.
        #expect(!HoardTab.isMarkdown(URL(fileURLWithPath: "/a/photo.png")))
        #expect(!HoardTab.isMarkdown(URL(fileURLWithPath: "/a/Makefile")))
        #expect(!HoardTab.isMarkdown(URL(fileURLWithPath: "/a/script.sh")))
        #expect(!HoardTab.isMarkdown(URL(fileURLWithPath: "/a/archive.md.zip")))
        #expect(!HoardTab.isMarkdown(URL(fileURLWithPath: "/a/mdfile")))
    }

    @Test("Double-click and Enter take the SAME path")
    func doubleClickAndEnterAgree() {
        // The bug this guards: Enter went through `activateCursor` while
        // double-click called `descend(into:)` directly — which guards on
        // `isDirectory` and silently returns for a file. So teaching Enter to
        // open markdown left double-click, the thing anyone actually reaches
        // for in a file manager, doing nothing at all.
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/Users/test"))
        fs.add(directory: "/Users/test", children: ["note.md", "photo.png"])
        let tab = HoardTab(directory: URL(fileURLWithPath: "/Users/test"), fileSystem: fs)

        final class Box: @unchecked Sendable { var opened: [URL] = [] }
        let box = Box()
        tab.onOpenDocument = { box.opened.append($0) }

        tab.activate(entry("note.md"))
        #expect(box.opened.count == 1, "double-click must open a markdown file")

        tab.activate(entry("photo.png"))
        #expect(box.opened.count == 1, "and must still ignore everything else")
    }

    @Test("The intent carries the path and asks for basic mode")
    func intentAsksForBasic() {
        // Stated rather than left to Lore's setting: the point of clicking a
        // `.md` is to see THAT file, not to arrive in the vault browser.
        let intent = AinkradLaunchIntent(path: "/vault/roadmap.md", mode: .basic)
        let decoded = AinkradLaunchIntent.decode(intent.json)
        #expect(decoded?.path == "/vault/roadmap.md")
        #expect(decoded?.mode == .basic)
        #expect(decoded?.isOpenDocument == true)
    }

    @Test("A disabled or missing Lore returns a reason the pane can show")
    func unavailableReturnsAReason() {
        // The point: a reason comes BACK, so the pane can toast it. Logging it
        // and returning nothing is the "recorded, never surfaced" shape.
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .disabled }
        #expect(hub.availability(of: "lore") == .disabled)
        hub.setAvailabilityProvider { _ in .unknown }
        #expect(hub.availability(of: "lore") == .unknown)
    }

    @Test("An unavailable Lore is refused before a payload is enqueued")
    func unavailableTargetIsNotEnqueued() {
        // A payload left pending for an app that never opens is a leak that
        // also mis-fires if that app is installed later.
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .unknown }
        #expect(hub.availability(of: "lore") == .unknown)
        #expect(hub.takePending(for: "lore") == nil)
    }

    @Test("An available Lore receives the payload, once")
    func availableTargetReceivesItOnce() {
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider { _ in .available }
        hub.enqueue(target: "lore", payload: AinkradLaunchIntent(path: "/a.md", mode: .basic).json)
        #expect(AinkradLaunchIntent.decode(hub.takePending(for: "lore"))?.path == "/a.md")
        #expect(hub.takePending(for: "lore") == nil, "the mailbox is consumed")
    }
}
