import Foundation
import Testing

@testable import Ainkrad

@Suite("Breadcrumb and status")
struct BreadcrumbTests {
    private func entry(_ name: String, size: Int64, dir: Bool = false) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/x/\(name)"), name: name, isDirectory: dir,
            isSymlink: false, isHidden: false, size: size, modified: Date())
    }

    @Test("splits a path into cumulative components")
    func components() {
        let parts = breadcrumbComponents(for: URL(fileURLWithPath: "/Users/test/Documents"))
        #expect(parts.map(\.name) == ["/", "Users", "test", "Documents"])
        #expect(parts.last?.url == URL(fileURLWithPath: "/Users/test/Documents"))
        #expect(parts[1].url == URL(fileURLWithPath: "/Users"))
    }

    @Test("root alone is a single component")
    func rootOnly() {
        #expect(breadcrumbComponents(for: URL(fileURLWithPath: "/")).map(\.name) == ["/"])
    }

    @Test("summarises the whole folder when nothing is selected")
    func summaryNoSelection() {
        let entries = [entry("a", size: 100), entry("b", size: 200)]
        #expect(selectionSummary(entries: entries, selection: []) == "2 items")
    }

    @Test("summarises the selection when there is one")
    func summaryWithSelection() {
        let entries = [entry("a", size: 100), entry("b", size: 200)]
        let summary = selectionSummary(entries: entries, selection: [entries[0].url])
        #expect(summary.hasPrefix("1 of 2 selected"))
        #expect(summary.contains("100"))
    }

    @Test("singular item reads naturally")
    func singular() {
        #expect(selectionSummary(entries: [entry("a", size: 1)], selection: []) == "1 item")
    }

    @Test("an empty folder says so")
    func emptyFolder() {
        #expect(selectionSummary(entries: [], selection: []) == "Empty")
    }
}
