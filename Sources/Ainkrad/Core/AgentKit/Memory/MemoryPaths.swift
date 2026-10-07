import AinkradHostRuntime
import Foundation

/// Resolves the on-disk layout of the host-internal memory subsystem: the
/// three markdown files, the SQLite index, the user profile, and per-session
/// transcripts. Memory is global (no per-workspace scoping) and app-managed.
struct MemoryPaths {
    let root: URL
    init(root: URL) { self.root = root }

    func url(for file: MemoryFile) -> URL { root.appendingPathComponent(file.rawValue) }
    var indexURL: URL { root.appendingPathComponent("index.sqlite") }
    var profileURL: URL { root.appendingPathComponent("profile.json") }
    var sessionsDir: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    func sessionURL(id: String) -> URL { sessionsDir.appendingPathComponent("\(id).md") }
}
