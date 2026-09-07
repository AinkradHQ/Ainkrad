import Testing
@testable import Ainkrad

@Suite("SignalBellButton badge")
struct SignalBellButtonTests {
    @Test("the badge appears only when something is unread")
    func badgeVisibility() {
        #expect(SignalBellButton.badgeText(0) == nil)
        #expect(SignalBellButton.badgeText(1) == "1")
        #expect(SignalBellButton.badgeText(42) == "42")
    }

    @Test("the badge caps so it cannot widen the top bar")
    func badgeCaps() {
        #expect(SignalBellButton.badgeText(99) == "99")
        #expect(SignalBellButton.badgeText(100) == "99+")
        #expect(SignalBellButton.badgeText(12_345) == "99+")
    }

    @Test("a muted bell shows a struck-through glyph, whatever the count")
    func mutedGlyph() {
        // Silence the user cannot SEE is indistinguishable from breakage, and
        // the report it generates is "notifications stopped working".
        #expect(SignalBellButton.glyphName(unread: 0, isMuted: true) == "bell.slash")
        #expect(SignalBellButton.glyphName(unread: 5, isMuted: true) == "bell.slash")
        #expect(SignalBellButton.glyphName(unread: 5, isMuted: false) == "bell.fill")
        #expect(SignalBellButton.glyphName(unread: 0, isMuted: false) == "bell")
    }
}
