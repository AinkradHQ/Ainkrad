import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// Characterizes the parts of Hoard's key map that live outside SwiftUI: the
/// function-key equivalents, and the one activation path that Enter, list
/// double-click and grid double-click all route through (MEMORY landmine —
/// fixing one opener once left the other two dead).
@MainActor
@Suite("Hoard keyboard handling")
struct HoardKeyboardHandlingTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeTab() -> HoardTab {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Documents/", "notes.md", "photo.png"])
        fs.add(directory: "/Users/test/Documents", children: ["report.pdf"])
        return HoardTab(directory: home, fileSystem: fs)
    }

    private func scalar(_ key: Int) -> Character? {
        UnicodeScalar(UInt32(key)).map(Character.init)
    }

    @Test("the operation keys are AppKit's F2, F5, F6 and F7 function keys")
    func functionKeys() {
        #expect(HoardKeyboardHandling.f2.character == scalar(NSF2FunctionKey))
        #expect(HoardKeyboardHandling.f5.character == scalar(NSF5FunctionKey))
        #expect(HoardKeyboardHandling.f6.character == scalar(NSF6FunctionKey))
        #expect(HoardKeyboardHandling.f7.character == scalar(NSF7FunctionKey))
    }

    @Test("Enter on a markdown file hands it to the document opener")
    func enterOpensMarkdown() {
        let tab = makeTab()
        var opened: [URL] = []
        tab.onOpenDocument = { opened.append($0) }
        tab.moveCursor(by: 1)
        #expect(tab.cursorEntry?.name == "notes.md")
        tab.activateCursor()
        #expect(opened == [home.appendingPathComponent("notes.md")])
    }

    @Test("double-click (activate) on a markdown file opens it like Enter does")
    func doubleClickOpensMarkdown() throws {
        let tab = makeTab()
        var opened: [URL] = []
        tab.onOpenDocument = { opened.append($0) }
        let entry = try #require(tab.visibleEntries.first { $0.name == "notes.md" })
        tab.activate(entry)
        #expect(opened == [entry.url])
    }

    @Test("activating a non-markdown file does nothing")
    func nonMarkdownIgnored() throws {
        let tab = makeTab()
        var opened: [URL] = []
        tab.onOpenDocument = { opened.append($0) }
        let entry = try #require(tab.visibleEntries.first { $0.name == "photo.png" })
        tab.activate(entry)
        #expect(opened.isEmpty)
        #expect(tab.currentDirectory == home)
    }

    @Test("activating a directory descends instead of opening")
    func activateDirectoryDescends() throws {
        let tab = makeTab()
        var opened: [URL] = []
        tab.onOpenDocument = { opened.append($0) }
        let entry = try #require(tab.visibleEntries.first { $0.name == "Documents" })
        tab.activate(entry)
        #expect(opened.isEmpty)
        #expect(tab.currentDirectory == home.appendingPathComponent("Documents"))
    }

    @Test("markdown detection is by extension, case-insensitive")
    func markdownExtensions() {
        for name in ["a.md", "b.MARKDOWN", "c.mdown", "d.mkd"] {
            #expect(HoardTab.isMarkdown(URL(fileURLWithPath: "/x/\(name)")))
        }
        #expect(!HoardTab.isMarkdown(URL(fileURLWithPath: "/x/e.txt")))
    }
}
