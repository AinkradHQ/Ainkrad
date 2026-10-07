import Foundation

/// Which column the list is ordered by.
enum FileSortKey: String, CaseIterable, Sendable {
    case name, size, modified, kind
}

/// Drops hidden entries unless `showHidden`. Pure.
func filteredEntries(_ entries: [FileEntry], showHidden: Bool) -> [FileEntry] {
    showHidden ? entries : entries.filter { !$0.isHidden }
}

/// Orders `entries` by `key`. Directories are grouped ahead of files by
/// default — the orthodox-file-manager convention, and the reason this can't
/// just delegate to the kit's `sortedRows` (which sorts one flat text column).
///
/// Name and kind comparisons use `localizedStandardCompare`, so `file2`
/// precedes `file10` the way the Finder orders them. Pure — no I/O.
func sortedEntries(
    _ entries: [FileEntry], by key: FileSortKey,
    ascending: Bool, directoriesFirst: Bool = true
) -> [FileEntry] {
    let ordered = entries.sorted { lhs, rhs in
        switch key {
        case .name:
            return compare(lhs.name, rhs.name, ascending: ascending)
        case .size:
            return lhs.size == rhs.size
                ? compare(lhs.name, rhs.name, ascending: true)
                : (ascending ? lhs.size < rhs.size : lhs.size > rhs.size)
        case .modified:
            return lhs.modified == rhs.modified
                ? compare(lhs.name, rhs.name, ascending: true)
                : (ascending ? lhs.modified < rhs.modified : lhs.modified > rhs.modified)
        case .kind:
            return lhs.fileExtension == rhs.fileExtension
                ? compare(lhs.name, rhs.name, ascending: true)
                : compare(lhs.fileExtension, rhs.fileExtension, ascending: ascending)
        }
    }
    guard directoriesFirst else { return ordered }
    // Stable partition: `filter` preserves relative order, so the sort above
    // survives the regrouping.
    return ordered.filter(\.isDirectory) + ordered.filter { !$0.isDirectory }
}

private func compare(_ lhs: String, _ rhs: String, ascending: Bool) -> Bool {
    let result = lhs.localizedStandardCompare(rhs)
    return ascending ? result == .orderedAscending : result == .orderedDescending
}
