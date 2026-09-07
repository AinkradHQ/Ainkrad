import Foundation

/// Owns the on-disk file layout for the three host-internal memory markdown
/// files (USER.md, MEMORY.md, AGENTS.md): read/write, lazy directory + file
/// creation on first write, and the size-capped always-loaded set consumed
/// by the assistant's context assembly.
@MainActor
final class MemoryStore {
    private let paths: MemoryPaths
    private let fm: FileManager
    var onChange: ((MemoryFile) -> Void)?

    init(paths: MemoryPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fm = fileManager
    }

    func read(_ file: MemoryFile) -> String {
        (try? String(contentsOf: paths.url(for: file), encoding: .utf8)) ?? ""
    }

    func write(_ text: String, to file: MemoryFile) {
        ensureRoot()
        let url = paths.url(for: file)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.persistence.error("Failed to write \(text.utf8.count, privacy: .public) bytes to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        onChange?(file)
    }

    func append(_ text: String, to file: MemoryFile) {
        let existing = read(file)
        let combined = existing.isEmpty ? text : existing + "\n" + text
        write(combined, to: file)
    }

    func alwaysLoadedSet(perFileCharCap: Int = 6000) -> [(MemoryFile, String)] {
        MemoryFile.allCases.compactMap { file in
            let text = read(file)
            guard !text.isEmpty else { return nil }
            return (file, Self.tailCap(text, perFileCharCap))
        }
    }

    private func ensureRoot() {
        try? fm.createDirectory(at: paths.root, withIntermediateDirectories: true)
    }

    private static func tailCap(_ text: String, _ cap: Int) -> String {
        guard text.count > cap else { return text }
        return String(text.suffix(cap))
    }
}
