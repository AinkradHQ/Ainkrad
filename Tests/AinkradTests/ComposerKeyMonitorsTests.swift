import AppKit
import Testing

@testable import Ainkrad

/// Pins the composer's two key tables before the Sage migration touches the
/// composer: which keystrokes cycle the agent, and which the palette/mention
/// overlay swallows.
@Suite struct ComposerKeyMonitorsTests {
    private let tab: UInt16 = 48

    @Test func plainTabAndShiftTabCycleTheAgent() {
        #expect(ComposerTabCycleMonitor.isCycleKey(keyCode: tab, modifiers: []))
        #expect(ComposerTabCycleMonitor.isCycleKey(keyCode: tab, modifiers: .shift))
    }

    @Test func tabWithAnyOtherModifierPassesThrough() {
        for flags: NSEvent.ModifierFlags in [.command, .option, .control, [.shift, .command], .capsLock] {
            #expect(!ComposerTabCycleMonitor.isCycleKey(keyCode: tab, modifiers: flags))
        }
    }

    @Test func otherKeysNeverCycle() {
        #expect(!ComposerTabCycleMonitor.isCycleKey(keyCode: 36, modifiers: []))
        #expect(!ComposerTabCycleMonitor.isCycleKey(keyCode: 126, modifiers: .shift))
    }

    @Test func overlaySwallowsArrowsAndBothReturnKeys() {
        #expect(ComposerOverlayKeyMonitor.key(for: 126) == .up)
        #expect(ComposerOverlayKeyMonitor.key(for: 125) == .down)
        #expect(ComposerOverlayKeyMonitor.key(for: 36) == .confirm)
        #expect(ComposerOverlayKeyMonitor.key(for: 76) == .confirm)
    }

    /// Esc (53) belongs to the floating panel's own monitor; Tab and letters
    /// keep reaching the composer.
    @Test func overlayPassesEverythingElseThrough() {
        for code: UInt16 in [53, 48, 0, 123, 124] {
            #expect(ComposerOverlayKeyMonitor.key(for: code) == nil)
        }
    }
}
