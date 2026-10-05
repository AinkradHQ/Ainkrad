import Foundation
import Testing

@testable import Ainkrad

@Suite("Push-to-talk shortcut")
struct PushToTalkShortcutTests {
    @Test func actionIsRegisteredAndRebindable() {
        #expect(ShortcutAction.allCases.contains(.pushToTalk))
        #expect(!ShortcutAction.pushToTalk.displayName.isEmpty)
    }

    @Test func defaultChordIsControlOptionSpace() {
        let chord = ShortcutAction.pushToTalk.defaultChord
        #expect(chord.keyCode == 49)
        #expect(chord.control)
        #expect(chord.option)
        #expect(!chord.command)
    }
}
