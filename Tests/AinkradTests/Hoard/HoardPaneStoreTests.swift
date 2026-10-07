import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Minimal in-memory `PersistenceStore` for these tests.
private final class MemoryPersistence: PersistenceStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    func load<T: PersistableDocument>(_ type: T.Type) -> T? {
        storage[T.documentID].flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    func save<T: PersistableDocument>(_ document: T) {
        storage[T.documentID] = try? JSONEncoder().encode(document)
    }
    func delete<T: PersistableDocument>(_ type: T.Type) {
        storage[T.documentID] = nil
    }
}

@MainActor
@Suite("HoardPaneStore")
struct HoardPaneStoreTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeFS() -> InMemoryFileSystem {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Documents/", "notes.txt"])
        fs.add(directory: "/Users/test/Documents", children: ["report.pdf"])
        return fs
    }

    @Test("opens with one tab rooted at home")
    func initialTab() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        #expect(store.tabs.count == 1)
        #expect(store.activeTab.currentDirectory == home)
    }

    @Test("new tab is appended and becomes active")
    func newTab() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        store.newTab()
        #expect(store.tabs.count == 2)
        #expect(store.activeTabIndex == 1)
    }

    @Test("new tab can open at a specific directory")
    func newTabAtPath() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        store.newTab(at: home.appendingPathComponent("Documents"))
        #expect(store.activeTab.currentDirectory == home.appendingPathComponent("Documents"))
    }

    @Test("closing a tab keeps the active index in range")
    func closeTab() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        store.newTab()
        store.newTab()
        #expect(store.activeTabIndex == 2)
        store.closeTab(at: 2)
        #expect(store.tabs.count == 2)
        #expect(store.activeTabIndex == 1)
    }

    @Test("closing the last remaining tab is refused")
    func cannotCloseLastTab() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        store.closeTab(at: 0)
        #expect(store.tabs.count == 1)
    }

    @Test("closing a tab before the active one shifts the index down")
    func closeBeforeActive() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        store.newTab()
        #expect(store.activeTabIndex == 1)
        store.closeTab(at: 0)
        #expect(store.activeTabIndex == 0)
    }

    @Test("selectTab ignores an out-of-range index")
    func selectTabClamps() {
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: MemoryPersistence())
        store.selectTab(at: 7)
        #expect(store.activeTabIndex == 0)
    }

    @Test("state round-trips through persistence")
    func persistence() {
        let persistence = MemoryPersistence()
        let store = HoardPaneStore(fileSystem: makeFS(), persistence: persistence)
        store.newTab(at: home.appendingPathComponent("Documents"))
        store.activeTab.showHidden = true
        store.persist()

        let restored = HoardPaneStore(fileSystem: makeFS(), persistence: persistence)
        #expect(restored.tabs.count == 2)
        #expect(restored.activeTabIndex == 1)
        #expect(restored.activeTab.currentDirectory == home.appendingPathComponent("Documents"))
        #expect(restored.activeTab.showHidden)
    }

    @Test("a restored tab whose directory has vanished falls back to home")
    func restoreMissingDirectory() {
        let persistence = MemoryPersistence()
        persistence.save(
            HoardPaneDocument(
                tabPaths: ["/Users/test/Documents", "/gone"],
                activeTabIndex: 1, showHidden: false,
                sortKey: "name", sortAscending: true))

        let store = HoardPaneStore(fileSystem: makeFS(), persistence: persistence)
        #expect(store.tabs.count == 2)
        #expect(store.tabs[1].currentDirectory == home)
    }
}
