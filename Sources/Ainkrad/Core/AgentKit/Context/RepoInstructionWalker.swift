import Foundation

/// Discovers the working repo's own instruction files by walking UP from the
/// active workspace root — the coding-agent convention (`CLAUDE.md` /
/// `AGENTS.md` at or above the project root). Pure and filesystem-injectable
/// so it is unit testable against a temp tree.
enum RepoInstructionWalker {
    static let filenames = ["CLAUDE.md", "AGENTS.md"]

    static func instructionFiles(
        startingAt start: URL, fileManager: FileManager = .default,
        maxDepth: Int = 40
    ) -> [URL] {
        var out: [URL] = []
        var dir = start.standardizedFileURL
        var depth = 0
        while depth < maxDepth {
            for name in filenames {
                let candidate = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                    out.append(candidate)
                }
            }
            if fileManager.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                break  // reached the repo root (inclusive) — never ascend above it
            }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }  // reached filesystem root
            dir = parent
            depth += 1
        }
        return out
    }
}
