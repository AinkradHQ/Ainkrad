import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

/// `PaneLocatorRegistry` is what lets a notification click land on the pane
/// that raised it (the 0.25.0 fix): each pane reports what it shows through a
/// per-block sink, and activation reads the locator back by block. Pinned
/// before the notifications area is refactored, so the per-block keying, the
/// clear-on-nil rule and the memoized sink cannot drift.
@MainActor
@Suite("Pane locator registry")
struct PaneLocatorRegistryTests {
    @Test func aReportedLocatorIsReadBackForItsOwnBlockOnly() {
        let registry = PaneLocatorRegistry()
        let first = UUID()
        let second = UUID()

        registry.set("session-1", forBlock: first)
        registry.set("session-2", forBlock: second)

        #expect(registry.locator(forBlock: first) == "session-1")
        #expect(registry.locator(forBlock: second) == "session-2")
        #expect(registry.locator(forBlock: UUID()) == nil)
    }

    @Test func nilOrEmptyClearsTheBlocksLocator() {
        let registry = PaneLocatorRegistry()
        let block = UUID()

        registry.set("session-1", forBlock: block)
        registry.set(nil, forBlock: block)
        #expect(registry.locator(forBlock: block) == nil)

        registry.set("session-1", forBlock: block)
        registry.set("", forBlock: block)
        #expect(registry.locator(forBlock: block) == nil)
    }

    @Test func theSinkIsMemoizedPerBlockAndRecordsIntoTheRegistry() {
        let registry = PaneLocatorRegistry()
        let block = UUID()

        let sink = registry.sink(forBlock: block)
        #expect(registry.sink(forBlock: block) == sink)
        #expect(registry.sink(forBlock: UUID()) != sink)

        sink("session-7")
        #expect(registry.locator(forBlock: block) == "session-7")
        sink(nil)
        #expect(registry.locator(forBlock: block) == nil)
    }

    @Test func forgettingABlockDropsItsLocatorAndItsSink() {
        let registry = PaneLocatorRegistry()
        let block = UUID()
        let sink = registry.sink(forBlock: block)
        sink("session-1")

        registry.forget(blockID: block)

        #expect(registry.locator(forBlock: block) == nil)
        #expect(registry.sink(forBlock: block) != sink)
    }
}
