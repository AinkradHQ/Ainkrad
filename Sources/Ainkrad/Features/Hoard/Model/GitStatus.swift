import Foundation

/// A file's state within its repository, reduced to what a browser row can
/// usefully show. Deliberately coarser than git's full XY matrix — a file
/// that is both staged and modified reads as `.modified`, because a one-glyph
/// gutter cannot express more than the headline.
enum GitFileStatus: Sendable, Equatable {
    case staged
    case modified
    case added
    case deleted
    case renamed
    case untracked
    case ignored
    case conflicted

    /// SF Symbol for the gutter.
    var glyph: String {
        switch self {
        case .staged: return "plus.circle.fill"
        case .modified: return "circle.fill"
        case .added: return "plus.circle"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        case .untracked: return "questionmark.circle"
        case .ignored: return "circle.dashed"
        case .conflicted: return "exclamationmark.triangle.fill"
        }
    }
}

/// One repository's status, keyed by path RELATIVE to the root.
///
/// Per-repo rather than per-directory: one `git status` call answers for the
/// whole tree, so navigating to a sibling folder is a cache hit rather than
/// another process spawn.
struct GitRepoStatus: Sendable, Equatable {
    var root: URL
    var branch: String?
    var entries: [String: GitFileStatus]

    /// Status for an absolute URL inside this repo, or `nil` if it is clean or
    /// outside the repo.
    func status(for url: URL) -> GitFileStatus? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return nil }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        if let exact = entries[relative] { return exact }
        // A directory is interesting when anything beneath it is. Cheap
        // prefix scan — directories are a small fraction of a listing.
        let prefix = relative.isEmpty ? "" : relative + "/"
        if !prefix.isEmpty, entries.keys.contains(where: { $0.hasPrefix(prefix) }) {
            return .modified
        }
        return nil
    }
}

/// Parses `git status --porcelain=v2 --branch --ignored`.
///
/// v2 rather than v1 or human output: it is an explicitly stable
/// machine-readable contract, carries the branch header, and puts staged and
/// unstaged state in fixed columns instead of v1's ambiguous rename encoding.
///
/// Unrecognised lines are skipped rather than throwing — a future git adding a
/// header must not blank the whole listing.
func parsePorcelainV2(_ output: String, root: URL) -> GitRepoStatus {
    var branch: String?
    var entries: [String: GitFileStatus] = [:]

    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
        let text = String(line)

        if text.hasPrefix("# branch.head ") {
            branch = String(text.dropFirst("# branch.head ".count))
            continue
        }
        if text.hasPrefix("#") { continue }

        guard let kind = text.first else { continue }
        switch kind {
        case "1", "2":
            // "1 XY sub mH mI mW hH hI path"
            // "2 XY sub mH mI mW hH hI X<score> path<TAB>origPath"
            let fields = text.split(
                separator: " ", maxSplits: kind == "1" ? 8 : 9,
                omittingEmptySubsequences: false)
            let expected = kind == "1" ? 9 : 10
            guard fields.count == expected else { continue }
            let xy = String(fields[1])
            // A rename's path field is "new\told" — the TAB is the separator,
            // and the NEW path is what the browser shows.
            let pathField = String(fields[expected - 1])
            let path = pathField.split(separator: "\t").first.map(String.init) ?? pathField
            entries[path] = status(fromXY: xy, isRename: kind == "2")

        case "u":
            let fields = text.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
            guard let path = fields.last else { continue }
            entries[String(path)] = .conflicted

        case "?":
            entries[String(text.dropFirst(2))] = .untracked

        case "!":
            entries[String(text.dropFirst(2))] = .ignored

        default:
            continue
        }
    }

    return GitRepoStatus(root: root, branch: branch, entries: entries)
}

/// `XY` is index-state then worktree-state. Worktree changes win the badge:
/// they are what the user is actively doing.
private func status(fromXY xy: String, isRename: Bool) -> GitFileStatus {
    guard xy.count == 2 else { return .modified }
    let index = xy[xy.startIndex]
    let worktree = xy[xy.index(after: xy.startIndex)]

    if isRename { return .renamed }
    if worktree == "D" || index == "D" { return .deleted }
    if worktree == "M" { return .modified }
    if index == "A" { return .added }
    if index == "M" || index == "R" || index == "C" { return .staged }
    return .modified
}
