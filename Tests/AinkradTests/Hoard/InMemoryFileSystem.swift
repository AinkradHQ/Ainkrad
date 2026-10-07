import Foundation

@testable import Ainkrad

/// Disk-free `FileSystemServing` for unit tests. Build a tree by path string;
/// every layer above the service protocol tests against this.
final class InMemoryFileSystem: FileSystemServing, @unchecked Sendable {
    /// Directory path → its children.
    private var tree: [String: [FileEntry]] = [:]
    let homeDirectory: URL

    init(home: URL = URL(fileURLWithPath: "/Users/test")) {
        self.homeDirectory = home
    }

    /// Registers `children` as the contents of `directory`. Names ending in
    /// "/" become directories.
    func add(directory: String, children: [String]) {
        let dirURL = URL(fileURLWithPath: directory)
        tree[dirURL.path] = children.map { raw in
            let isDir = raw.hasSuffix("/")
            let name = isDir ? String(raw.dropLast()) : raw
            return FileEntry(
                url: dirURL.appendingPathComponent(name),
                name: name,
                isDirectory: isDir,
                isSymlink: false,
                isHidden: name.hasPrefix("."),
                size: isDir ? 0 : Int64(name.count),
                modified: Date(timeIntervalSince1970: 0)
            )
        }
    }

    struct MissingDirectory: Error { let path: String }

    func contents(of directory: URL) throws -> [FileEntry] {
        guard let children = tree[directory.path] else {
            throw MissingDirectory(path: directory.path)
        }
        return children
    }

    func isDirectory(_ url: URL) -> Bool { tree[url.path] != nil }

    func exists(_ url: URL) -> Bool {
        if tree[url.path] != nil { return true }
        let parent = url.deletingLastPathComponent().path
        return tree[parent]?.contains { $0.name == url.lastPathComponent } ?? false
    }
}
