import AppKit
import Testing

@testable import Ainkrad

/// Pins which keystrokes cycle the agent. The overlay's key table moved to the
/// kit with the overlay (`AinkradComposerTests`).
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
}
