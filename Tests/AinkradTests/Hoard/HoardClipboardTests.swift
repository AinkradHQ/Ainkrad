import AppKit
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("Hoard clipboard", .serialized)
struct HoardClipboardTests {
    /// A private pasteboard, so tests never disturb the user's real clipboard.
    private func makeClipboard() -> (HoardClipboard, NSPasteboard) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("files-tests-\(UUID().uuidString)"))
        return (HoardClipboard(pasteboard: pasteboard), pasteboard)
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("starts empty")
    func startsEmpty() {
        let (clipboard, _) = makeClipboard()
        #expect(!clipboard.hasContents)
        #expect(clipboard.pendingOperation() == nil)
    }

    @Test("copy stores the paths and pastes as a copy")
    func copy() {
        let (clipboard, _) = makeClipboard()
        clipboard.copy([url("/a/one.txt"), url("/a/two.txt")])

        #expect(clipboard.hasContents)
        let pending = clipboard.pendingOperation()
        #expect(pending?.urls.count == 2)
        #expect(pending?.isMove == false)
    }

    @Test("cut marks the paths and pastes as a move")
    func cut() {
        let (clipboard, _) = makeClipboard()
        clipboard.cut([url("/a/one.txt")])

        #expect(clipboard.isCut(url("/a/one.txt")))
        #expect(clipboard.pendingOperation()?.isMove == true)
    }

    @Test("copying after a cut clears the cut marks")
    func copyClearsCut() {
        let (clipboard, _) = makeClipboard()
        clipboard.cut([url("/a/one.txt")])
        clipboard.copy([url("/a/two.txt")])

        #expect(!clipboard.isCut(url("/a/one.txt")))
        #expect(clipboard.pendingOperation()?.isMove == false)
    }

    // Writing to the real pasteboard is what makes Finder interop work in both
    // directions — this is the assertion that pins it.
    @Test("paths are written to the system pasteboard for other apps to read")
    func writesToPasteboard() {
        let (clipboard, pasteboard) = makeClipboard()
        clipboard.copy([url("/a/one.txt")])

        let read =
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(read?.first?.path == "/a/one.txt")
    }

    @Test("paths another app copied are pasteable here")
    func readsForeignPasteboardContents() {
        let (clipboard, pasteboard) = makeClipboard()
        // Simulate the Finder having copied a file.
        pasteboard.clearContents()
        pasteboard.writeObjects([url("/elsewhere/from-finder.txt") as NSURL])

        #expect(clipboard.hasContents)
        #expect(clipboard.pendingOperation()?.urls.first?.path == "/elsewhere/from-finder.txt")
        // Not ours, so it must paste as a COPY — moving another app's files
        // because we happen to be in cut mode would be wrong.
        #expect(clipboard.pendingOperation()?.isMove == false)
    }

    // The subtle one: we cut, then another app copied. Our cut state is stale,
    // and treating their paths as a move would relocate files they only copied.
    @Test("a stale cut does not turn another app's copy into a move")
    func staleCutDoesNotMoveForeignPaths() {
        let (clipboard, pasteboard) = makeClipboard()
        clipboard.cut([url("/a/ours.txt")])

        pasteboard.clearContents()
        pasteboard.writeObjects([url("/b/theirs.txt") as NSURL])

        #expect(clipboard.pendingOperation()?.isMove == false)
    }

    @Test("clearing after a move empties the pasteboard and the marks")
    func clearAfterMove() {
        let (clipboard, _) = makeClipboard()
        clipboard.cut([url("/a/one.txt")])
        clipboard.clearAfterMove()

        #expect(!clipboard.hasContents)
        #expect(!clipboard.isCut(url("/a/one.txt")))
    }

    @Test("copying nothing is a no-op")
    func copyEmpty() {
        let (clipboard, _) = makeClipboard()
        clipboard.copy([])
        #expect(!clipboard.hasContents)
    }
}
