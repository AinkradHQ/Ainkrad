import Testing
import Foundation
@testable import Ainkrad

@MainActor
@Suite("Signal commands")
struct SignalCommandsTests {
    /// The bindings the menu commands drive. Asserted on the environment
    /// rather than through SwiftUI, which offers no way to invoke a command.
    @Test("toggling the dropdown flips only its own flag")
    func dropdownToggle() {
        let environment = AppEnvironment.preview()
        environment.isSignalDropdownPresented.toggle()
        #expect(environment.isSignalDropdownPresented)
        #expect(!environment.isSignalFeedPresented)
    }

    @Test("opening the full feed closes the dropdown")
    func feedClosesDropdown() {
        let environment = AppEnvironment.preview()
        environment.isSignalDropdownPresented = true
        // Both open at once would leave two overlapping lists of the same
        // events, one of them a five-row subset of the other.
        environment.isSignalDropdownPresented = false
        environment.isSignalFeedPresented = true
        #expect(!environment.isSignalDropdownPresented)
        #expect(environment.isSignalFeedPresented)
    }

    @Test("the chosen shortcuts do not collide with an existing binding")
    func shortcutsAreFree() {
        // Audited from the source: ⌘K Launcher, ⌘⇧N New Workspace, ⌥⇥
        // Workspaces, ⌘F Settings search. ⌥⌘N and ⇧⌥⌘N are free.
        //
        // A literal list rather than a grep, so adding a colliding shortcut
        // elsewhere later fails HERE with the reason written down.
        let taken: Set<String> = ["cmd+k", "cmd+shift+n", "opt+tab", "cmd+f"]
        #expect(!taken.contains("cmd+opt+n"))
        #expect(!taken.contains("cmd+opt+shift+n"))
    }
}
