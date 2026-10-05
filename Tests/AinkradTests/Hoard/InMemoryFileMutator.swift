import Foundation

@testable import Ainkrad

/// Disk-free `FileMutating`. Files are paths mapped to contents; directories
/// are paths mapped to nothing. Volume identity is assigned by path prefix so
/// cross-volume moves can be exercised without a second physical disk — which
/// is the whole reason this fake exists.
/// Not `final`: the undo-refusal tests subclass this to force modification
/// dates and volume availability, which is the only way to exercise "the file
/// changed" and "the disk was ejected" without a real ejectable disk.
class InMemoryFileMutator: FileMutating, @unchecked Sendable {
    struct Failure: Error { let reason: String }

    private var files: [String: String] = [:]
    private var directories: Set<String> = []
    /// path prefix → volume id. Longest match wins.
    private var volumes: [String: String] = ["/": "root"]
    /// Paths that throw on any mutation, for failure-path tests.
    var unwritablePaths: Set<String> = []

    init() {}

    // MARK: - Fixture building

    func addFile(_ path: String, contents: String = "x") {
        files[path] = contents
        var parent = (path as NSString).deletingLastPathComponent
        while parent != "/" && !parent.isEmpty {
            directories.insert(parent)
            parent = (parent as NSString).deletingLastPathComponent
        }
    }

    func addDirectory(_ path: String) { directories.insert(path) }

    /// Everything under `prefix` reports `volume`.
    func mountVolume(_ volume: String, at prefix: String) { volumes[prefix] = volume }

    func contents(of path: String) -> String? { files[path] }
    var allPaths: Set<String> { Set(files.keys).union(directories) }

    // MARK: - FileMutating

    func copyItem(at source: URL, to destination: URL) throws {
        try guardWritable(destination)
        guard fileExists(source) else { throw Failure(reason: "missing source") }
        if let contents = files[source.path] {
            files[destination.path] = contents
        } else {
            directories.insert(destination.path)
        }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try guardWritable(destination)
        guard fileExists(source) else { throw Failure(reason: "missing source") }
        if let contents = files.removeValue(forKey: source.path) {
            files[destination.path] = contents
        } else {
            directories.remove(source.path)
            directories.insert(destination.path)
        }
    }

    func createDirectory(at url: URL) throws {
        try guardWritable(url)
        directories.insert(url.path)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
    }

    func fileExists(_ url: URL) -> Bool {
        files[url.path] != nil || directories.contains(url.path)
    }

    func isDirectory(_ url: URL) -> Bool { directories.contains(url.path) }

    func childNames(of directory: URL) -> Set<String> {
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return Set(
            allPaths.compactMap { path -> String? in
                guard path.hasPrefix(prefix) else { return nil }
                let remainder = String(path.dropFirst(prefix.count))
                return remainder.contains("/") ? nil : remainder
            })
    }

    func modificationDate(of url: URL) -> Date? {
        fileExists(url) ? Date(timeIntervalSince1970: 0) : nil
    }

    func volumeIdentifier(for url: URL) -> String? {
        volumes
            .filter { url.path.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    private func guardWritable(_ url: URL) throws {
        if unwritablePaths.contains(url.path) {
            throw Failure(reason: "permission denied")
        }
    }
}
