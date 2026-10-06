import Foundation
import Testing

@testable import Ainkrad

/// Characterizes `HoardSearchStore` before the Hoard migration touches it:
/// the finder palette's open/close state, the debounced streaming search, the
/// jump palette's immediate listing, and the in-pane scoped search.
@MainActor
@Suite("Hoard search store", .timeLimit(.minutes(1)))
struct HoardSearchStoreTests {
    private let root = URL(fileURLWithPath: "/root")

    private func makeStore() -> HoardSearchStore {
        let fs = InMemoryFileSystem(home: root)
        fs.add(directory: "/root", children: ["src/", "README.md", "notes.txt"])
        fs.add(directory: "/root/src", children: ["main.swift", "helper.swift"])
        return HoardSearchStore(fileSystem: fs)
    }

    /// Polls the main actor until `condition` holds; the store's searches run
    /// on detached tasks and stream back, so there is no single await point.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a fresh store has no palette and no scoped query")
    func freshStore() {
        let store = makeStore()
        #expect(store.mode == nil)
        #expect(!store.isActive)
        #expect(!store.isScoped)
        #expect(store.results.isEmpty)
    }

    @Test("global search streams debounced results for the typed query")
    func globalSearch() async {
        let store = makeStore()
        store.open(.globalSearch, root: root)
        #expect(store.isActive)
        #expect(store.results.isEmpty)
        store.queryText = "swift"
        await waitUntil { !store.isSearching && !store.results.isEmpty }
        #expect(store.results.map(\.entry.name).sorted() == ["helper.swift", "main.swift"])
        #expect(!store.didTruncate)
    }

    @Test("clearing the global query empties the results without searching")
    func globalSearchEmptyQuery() async {
        let store = makeStore()
        store.open(.globalSearch, root: root)
        store.queryText = "swift"
        await waitUntil { !store.results.isEmpty }
        store.queryText = ""
        #expect(store.results.isEmpty)
        #expect(!store.isSearching)
    }

    @Test("the jump palette lists every entry without a query")
    func jumpListsEverything() async {
        let store = makeStore()
        store.open(.jump, root: root)
        #expect(store.isSearching)
        await waitUntil { !store.isSearching }
        let names = Set(store.results.map(\.entry.name))
        #expect(names.isSuperset(of: ["README.md", "notes.txt", "main.swift", "helper.swift"]))
        #expect(store.rankedResults.count == store.results.count)
    }

    @Test("the jump palette ranks by fuzzy match once a query is typed")
    func jumpRanks() async {
        let store = makeStore()
        store.open(.jump, root: root)
        await waitUntil { !store.isSearching }
        store.queryText = "main"
        #expect(store.rankedResults.first?.entry.name == "main.swift")
    }

    @Test("closing the palette resets mode, query and results")
    func closeResets() async {
        let store = makeStore()
        store.open(.jump, root: root)
        await waitUntil { !store.isSearching }
        store.close()
        #expect(store.mode == nil)
        #expect(store.queryText.isEmpty)
        #expect(store.results.isEmpty)
        #expect(!store.isSearching)
    }

    @Test("the scoped field searches below its root and clears back to the folder")
    func scopedSearch() async {
        let store = makeStore()
        store.scopedRoot = root
        store.scopedText = "notes"
        #expect(store.isScoped)
        await waitUntil { !store.isScopedSearching && !store.scopedResults.isEmpty }
        #expect(store.scopedResults.map(\.entry.name) == ["notes.txt"])
        store.clearScoped()
        #expect(!store.isScoped)
        #expect(store.scopedResults.isEmpty)
        #expect(!store.isScopedSearching)
    }

    @Test("a scoped query with no root yields nothing")
    func scopedWithoutRoot() async {
        let store = makeStore()
        store.scopedText = "notes"
        #expect(store.scopedResults.isEmpty)
        #expect(!store.isScopedSearching)
    }

    @Test("the scoped field is independent of the global palette")
    func scopedIndependent() async {
        let store = makeStore()
        store.scopedRoot = root
        store.scopedText = "notes"
        await waitUntil { !store.scopedResults.isEmpty }
        store.open(.globalSearch, root: root)
        store.close()
        #expect(store.scopedText == "notes")
        #expect(store.scopedResults.map(\.entry.name) == ["notes.txt"])
    }
}
