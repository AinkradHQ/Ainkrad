import Foundation
import Testing

@testable import Ainkrad

@Suite("File sorting and filtering")
struct FileSortingTests {
    private func entry(
        _ name: String, dir: Bool = false, size: Int64 = 0,
        modified: TimeInterval = 0
    ) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/x/\(name)"), name: name,
            isDirectory: dir, isSymlink: false, isHidden: name.hasPrefix("."),
            size: size, modified: Date(timeIntervalSince1970: modified))
    }

    @Test("hides dotfiles unless asked")
    func filtersHidden() {
        let entries = [entry("a.txt"), entry(".git", dir: true), entry("b.txt")]
        #expect(filteredEntries(entries, showHidden: false).map(\.name) == ["a.txt", "b.txt"])
        #expect(filteredEntries(entries, showHidden: true).count == 3)
    }

    @Test("directories sort before files regardless of key")
    func directoriesFirst() {
        let entries = [entry("z.txt"), entry("a-dir", dir: true), entry("a.txt")]
        let sorted = sortedEntries(entries, by: .name, ascending: true)
        #expect(sorted.map(\.name) == ["a-dir", "a.txt", "z.txt"])
    }

    @Test("directoriesFirst can be disabled")
    func directoriesInline() {
        // "zdir" sorts last by name, so it only leads if grouping is applied.
        let entries = [entry("zdir", dir: true), entry("apple.txt")]
        let grouped = sortedEntries(entries, by: .name, ascending: true)
        #expect(grouped.map(\.name) == ["zdir", "apple.txt"])
        let inline = sortedEntries(entries, by: .name, ascending: true, directoriesFirst: false)
        #expect(inline.map(\.name) == ["apple.txt", "zdir"])
    }

    @Test("name sort is natural, not lexicographic")
    func naturalNameSort() {
        let entries = [entry("file10.txt"), entry("file2.txt"), entry("file1.txt")]
        let sorted = sortedEntries(entries, by: .name, ascending: true)
        #expect(sorted.map(\.name) == ["file1.txt", "file2.txt", "file10.txt"])
    }

    @Test("descending reverses within the directory group")
    func descending() {
        let entries = [entry("a.txt"), entry("b.txt"), entry("d", dir: true)]
        let sorted = sortedEntries(entries, by: .name, ascending: false)
        #expect(sorted.map(\.name) == ["d", "b.txt", "a.txt"])
    }

    @Test("size sort is numeric")
    func sizeSort() {
        let entries = [entry("a", size: 100), entry("b", size: 9), entry("c", size: 1000)]
        let sorted = sortedEntries(entries, by: .size, ascending: true)
        #expect(sorted.map(\.name) == ["b", "a", "c"])
    }

    @Test("modified sort is chronological")
    func modifiedSort() {
        let entries = [entry("a", modified: 300), entry("b", modified: 100), entry("c", modified: 200)]
        let sorted = sortedEntries(entries, by: .modified, ascending: true)
        #expect(sorted.map(\.name) == ["b", "c", "a"])
    }

    @Test("kind sort groups by extension, then name")
    func kindSort() {
        let entries = [entry("b.swift"), entry("a.txt"), entry("a.swift")]
        let sorted = sortedEntries(entries, by: .kind, ascending: true)
        #expect(sorted.map(\.name) == ["a.swift", "b.swift", "a.txt"])
    }

    @Test("empty input stays empty")
    func empty() {
        #expect(sortedEntries([], by: .name, ascending: true).isEmpty)
        #expect(filteredEntries([], showHidden: true).isEmpty)
    }
}
