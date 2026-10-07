import Foundation
import Testing

@testable import Ainkrad

@Suite("NavigationHistory")
struct NavigationHistoryTests {
    private let a = URL(fileURLWithPath: "/a")
    private let b = URL(fileURLWithPath: "/b")
    private let c = URL(fileURLWithPath: "/c")

    @Test("starts at its root with nowhere to go")
    func initialState() {
        let history = NavigationHistory(root: a)
        #expect(history.current == a)
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test("visiting moves forward and enables back")
    func visit() {
        var history = NavigationHistory(root: a)
        history.visit(b)
        #expect(history.current == b)
        #expect(history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test("back then forward round-trips")
    func backForward() {
        var history = NavigationHistory(root: a)
        history.visit(b)
        history.goBack()
        #expect(history.current == a)
        #expect(history.canGoForward)
        history.goForward()
        #expect(history.current == b)
    }

    @Test("visiting after going back truncates the forward branch")
    func truncatesForward() {
        var history = NavigationHistory(root: a)
        history.visit(b)
        history.goBack()
        history.visit(c)
        #expect(history.current == c)
        #expect(!history.canGoForward)
        history.goBack()
        #expect(history.current == a)
    }

    @Test("re-visiting the current directory is a no-op")
    func visitingCurrentIsNoop() {
        var history = NavigationHistory(root: a)
        history.visit(a)
        #expect(!history.canGoBack)
    }

    @Test("canonicalises trailing slashes so URL equality works")
    func canonicalisesTrailingSlash() {
        // `deletingLastPathComponent()` produces a trailing slash; without
        // canonicalisation "/a/" != "/a" and ascend-to-parent silently fails.
        var history = NavigationHistory(root: URL(fileURLWithPath: "/a/b"))
        history.visit(URL(fileURLWithPath: "/a/b").deletingLastPathComponent())
        #expect(history.current == URL(fileURLWithPath: "/a"))
        // Re-visiting the same directory via the slashed form is still a no-op.
        history.visit(URL(fileURLWithPath: "/a/"))
        #expect(history.entries.count == 2)
    }

    @Test("back and forward at the ends do nothing")
    func clampsAtEnds() {
        var history = NavigationHistory(root: a)
        history.goBack()
        #expect(history.current == a)
        history.goForward()
        #expect(history.current == a)
    }
}
