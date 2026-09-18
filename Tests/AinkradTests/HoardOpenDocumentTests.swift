import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

/// Enter on a file in Hoard. E5 of the Basic Mode milestone.
@Suite("Hoard — open a document")
@MainActor
struct HoardOpenDocumentTests {

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
