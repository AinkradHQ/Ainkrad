import Foundation

/// The mutation seam. M1's `FileSystemServing` only READS, so every
/// destructive path here would otherwise have to touch the real disk to be
/// tested — including overwrite and cross-volume move, the two cases most
/// worth testing and least safe to run for real.
protocol FileMutating: Sendable {
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func createDirectory(at url: URL) throws
    func removeItem(at url: URL) throws
    func fileExists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    func childNames(of directory: URL) -> Set<String>
    func modificationDate(of url: URL) -> Date?
    /// Identifies the volume `url` lives on, so the engine can serialise work
    /// per physical device and detect cross-volume moves. Returns `nil` when
    /// the volume can't be resolved — treated as "unknown", which the engine
    /// handles by assuming a cross-volume move (the safe, invertible path).
    func volumeIdentifier(for url: URL) -> String?
}

struct LocalFileMutator: FileMutating {
    func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func childNames(of directory: URL) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return Set(names ?? [])
    }

    func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func volumeIdentifier(for url: URL) -> String? {
        guard
            let identifier = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
                .volumeIdentifier
        else { return nil }
        // `NSCopying & NSObjectProtocol`, opaque by design — its description is
        // stable within a process, which is all the queue key needs.
        return String(describing: identifier)
    }
}
