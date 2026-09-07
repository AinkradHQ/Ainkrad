import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Signal view state")
struct SignalViewStateTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-view-\(UUID().uuidString).json")
    }

    @Test("a fresh state shows everything, grouped by time")
    func defaults() {
        let state = SignalViewState()
        #expect(state.isShowingEverything)
        #expect(state.grouping == .byTime)
        #expect(state.filter.sources == nil)
        #expect(state.filter.severities == nil)
        #expect(state.filter.unreadOnly == false)
    }

    @Test("the filter mirrors the visible view, so scoped actions match the screen")
    func filterMirrorsView() {
        var state = SignalViewState()
        state.selectedSource = .app(appID: "raven")
        state.severities = [.failure]
        state.unreadOnly = true
        // Mark-all-read uses this. If it did not match what is on screen, the
        // user would clear rows they cannot see — and without markUnread that
        // was unrecoverable.
        #expect(state.filter.sources == [.app(appID: "raven")])
        #expect(state.filter.severities == [.failure])
        #expect(state.filter.unreadOnly)
        #expect(!state.isShowingEverything)
    }

    @Test("grouping and collapse are presentation only, absent from the filter")
    func groupingIsNotAFilter() {
        var state = SignalViewState()
        state.grouping = .bySource
        state.collapsedSources = ["app(appID: \"raven\")"]
        #expect(state.filter.sources == nil, "collapsing a group hides nothing from a query")
    }

    @Test("state survives a round trip through disk")
    func roundTrips() {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        var state = SignalViewState()
        state.grouping = .bySource
        state.severities = [.warning, .failure]
        state.unreadOnly = true
        state.selectedSource = .app(appID: "rune")
        state.collapsedSources = ["a", "b"]

        let store = SignalViewStateStore(url: file)
        store.save(state)

        #expect(store.load() == state)
    }

    @Test("a missing file loads defaults rather than failing")
    func missingFile() {
        #expect(SignalViewStateStore(url: url()).load() == SignalViewState())
    }

    @Test("a corrupt file loads defaults rather than refusing")
    func corruptFile() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{ not json".utf8).write(to: file)
        #expect(SignalViewStateStore(url: file).load() == SignalViewState())
    }

    @Test("a file missing newer fields keeps the rest")
    func partialFile() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"grouping":"bySource"}"#.utf8).write(to: file)
        let loaded = SignalViewStateStore(url: file).load()
        // Tolerant like every other stored shape here: one unknown or absent
        // field must not reset the whole view.
        #expect(loaded.grouping == .bySource)
        #expect(loaded.severities.isEmpty)
        #expect(!loaded.unreadOnly)
    }

    @Test("the failures view is the one people rebuild by hand")
    func failuresPreset() {
        #expect(SignalViewState.failures.severities == [.failure])
        #expect(SignalViewState.failures.unreadOnly)
    }
}
