import Foundation

/// Creating and extracting archives.
///
/// Shells out to the system `ditto` and `tar` rather than linking a
/// compression library: they are always present, they preserve macOS resource
/// forks and extended attributes (which a naive zip implementation silently
/// drops), and `ditto` produces archives the Finder can open.
protocol Archiving: Sendable {
    /// Zips `sources` into `destination`. Returns the archive URL.
    func archive(_ sources: [URL], to destination: URL) throws -> URL
    /// Extracts `archive` into `directory`. Returns the created top-level URLs.
    func extract(_ archive: URL, into directory: URL) throws -> [URL]
    /// Whether this extension is one we can extract.
    func canExtract(_ url: URL) -> Bool
}

struct SystemArchiveService: Archiving {
    private static let tarExtensions: Set<String> = ["tar", "gz", "tgz", "bz2", "xz"]

    func canExtract(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || Self.tarExtensions.contains(ext)
    }

    func archive(_ sources: [URL], to destination: URL) throws -> URL {
        guard !sources.isEmpty else { throw ArchiveFailure(reason: "Nothing to archive.") }

        // `ditto -c -k --sequesterRsrc` keeps resource forks, like the Finder's
        // "Compress".
        //
        // `--keepParent` only for a single DIRECTORY: it embeds the source's
        // enclosing name, so a folder zips as `project/…` (wanted) but a lone
        // file would zip as `enclosing-folder/file.txt` (not wanted, and not
        // what the Finder does).
        var arguments = ["-c", "-k", "--sequesterRsrc"]
        let isSingleDirectory =
            sources.count == 1
            && (try? sources[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isSingleDirectory { arguments.append("--keepParent") }
        arguments += sources.map(\.path)
        arguments.append(destination.path)

        try run("/usr/bin/ditto", arguments)
        return destination
    }

    func extract(_ archive: URL, into directory: URL) throws -> [URL] {
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])

        let ext = archive.pathExtension.lowercased()
        if ext == "zip" {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        } else if Self.tarExtensions.contains(ext) {
            // `tar` auto-detects the compression from the file itself.
            try run("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path])
        } else {
            throw ArchiveFailure(reason: "“\(ext)” is not an archive we can extract.")
        }

        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        // Diffing before/after is how we learn what was created — neither tool
        // reports its top-level entries in a machine-readable way.
        return after.subtracting(before).map { directory.appendingPathComponent($0) }
    }

    private func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()

        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ArchiveFailure(
                reason: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

struct ArchiveFailure: Error {
    let reason: String
}

/// Default archive name for a selection: the single item's name, or the
/// enclosing folder's name for a multi-selection — matching the Finder, and
/// avoiding "Archive.zip" collisions.
func defaultArchiveName(for sources: [URL], in directory: URL) -> String {
    let base: String
    if sources.count == 1 {
        base = sources[0].deletingPathExtension().lastPathComponent
    } else {
        base = directory.lastPathComponent
    }
    return base.isEmpty ? "Archive.zip" : "\(base).zip"
}
