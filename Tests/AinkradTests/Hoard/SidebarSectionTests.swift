import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Sidebar sections")
struct SidebarSectionTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test("with no pins or repos there is only the places group")
    func placesOnly() {
        let sections = sidebarSections(home: home)
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].roots.first?.name == "Home")
    }

    // Empty groups must not render as bare headings.
    @Test("an empty favourites list produces no favourites group")
    func noEmptyGroups() {
        let sections = sidebarSections(home: home, pinned: [], repositories: [])
        #expect(!sections.contains { $0.title == "Favourites" })
        #expect(!sections.contains { $0.title == "Repositories" })
    }

    @Test("pins become a removable favourites group")
    func favourites() {
        let sections = sidebarSections(
            home: home,
            pinned: [URL(fileURLWithPath: "/work/thing")])
        let favourites = sections.first { $0.title == "Favourites" }
        #expect(favourites?.roots.first?.name == "thing")
        #expect(favourites?.isRemovable == true)
    }

    // Repositories are discovered, not pinned, so removing one makes no sense.
    @Test("repositories are not removable")
    func repositoriesAreNotRemovable() {
        let sections = sidebarSections(
            home: home,
            repositories: [URL(fileURLWithPath: "/work/repo")])
        #expect(sections.first { $0.title == "Repositories" }?.isRemovable == false)
    }

    @Test("a pinned folder that is already a standard place is not shown twice")
    func noDuplicateOfStandardPlace() {
        let sections = sidebarSections(
            home: home, pinned: [home.appendingPathComponent("Documents")])
        #expect(!sections.contains { $0.title == "Favourites" })
    }

    @Test("ids are unique across groups so ForEach stays stable")
    func uniqueIDs() {
        let sections = sidebarSections(
            home: home,
            pinned: [URL(fileURLWithPath: "/work/thing")],
            repositories: [URL(fileURLWithPath: "/work/thing")])
        let ids = sections.flatMap { $0.roots.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }
}

@MainActor
@Suite("Pinned roots")
struct HoardPinnedRootsTests {
    private func makePins() -> HoardPinnedRoots {
        HoardPinnedRoots(persistence: InMemoryPersistenceStore())
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("pinning adds a root, unpinning removes it")
    func pinAndUnpin() {
        let pins = makePins()
        pins.pin(url("/work/thing"))
        #expect(pins.isPinned(url("/work/thing")))

        pins.unpin(url("/work/thing"))
        #expect(!pins.isPinned(url("/work/thing")))
    }

    @Test("pinning the same folder twice does not duplicate the row")
    func noDuplicates() {
        let pins = makePins()
        pins.pin(url("/work/thing"))
        pins.pin(url("/work/thing"))
        #expect(pins.roots.count == 1)
    }

    // Paths that differ only textually are the same folder — the trailing
    // slash problem that broke `ascend()` back in M1.
    @Test("a trailing slash is the same folder, not a second pin")
    func standardisesPaths() {
        let pins = makePins()
        pins.pin(url("/work/thing"))
        #expect(pins.isPinned(URL(fileURLWithPath: "/work/thing/")))
    }

    @Test("pins survive a relaunch")
    func persists() {
        let persistence = InMemoryPersistenceStore()
        let first = HoardPinnedRoots(persistence: persistence)
        first.pin(url("/work/thing"))

        let second = HoardPinnedRoots(persistence: persistence)
        #expect(second.isPinned(url("/work/thing")))
    }
}
