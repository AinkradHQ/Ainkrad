import Foundation

/// `FileManager`-backed implementation. Stateless and `Sendable` — it holds no
/// cached handles, so it is safe to share across actors.
struct LocalFileSystemService: FileSystemServing {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey, .nameKey,
    ]

    var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }

    func contents(of directory: URL) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Self.keys,
            // Do NOT skip hidden files here: hiding them is a VIEW concern
            // (⌘. toggles it), so the service always reports the truth.
            options: []
        )
        return urls.map { entry(for: $0) }
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// A per-item failure degrades to sensible defaults rather than failing the
    /// whole listing — one unreadable item must not blank the directory.
    private func entry(for url: URL) -> FileEntry {
        let values = try? url.resourceValues(forKeys: Set(Self.keys))
        return FileEntry(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            isDirectory: values?.isDirectory ?? false,
            isSymlink: values?.isSymbolicLink ?? false,
            isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            size: Int64(values?.fileSize ?? 0),
            modified: values?.contentModificationDate ?? .distantPast
        )
    }
}
