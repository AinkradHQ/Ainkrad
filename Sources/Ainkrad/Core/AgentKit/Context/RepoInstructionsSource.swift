import AinkradAppKit
import Foundation
import Observation

/// Publishes the working repo's own instruction files (`CLAUDE.md` /
/// `AGENTS.md`, discovered by `RepoInstructionWalker`) as a single
/// workspace-context snapshot under a DISTINCT `kind` from the host's own
/// memory. mtime-cached: the hub polls `snapshot()` each turn, but a file is
/// only re-read when its modification date changes, so an edited instruction
/// file is picked up without a filesystem watcher. Each file is per-file
/// capped; `AgentContextService.perSourceCharBudget` still bounds the total.
@MainActor
@Observable
final class RepoInstructionsLoader {
    static let kind = "repo-instructions"
    private static let truncationMarker = "…[truncated]"

    private let root: URL
    private let perFileCharCap: Int
    private let fm: FileManager
    private struct CacheEntry {
        let mtime: Date?
        let text: String
    }
    private var cache: [String: CacheEntry] = [:]

    init(root: URL, perFileCharCap: Int = 6000, fileManager: FileManager = .default) {
        self.root = root
        self.perFileCharCap = perFileCharCap
        self.fm = fileManager
    }

    func snapshot() -> AgentContextSnapshot? {
        let files = RepoInstructionWalker.instructionFiles(startingAt: root, fileManager: fm)
        var sections: [String] = []
        for url in files {
            guard let text = readCached(url) else { continue }
            sections.append("### \(url.path)\n\(text)")
        }
        guard !sections.isEmpty else { return nil }
        return AgentContextSnapshot(
            kind: Self.kind,
            title: "Repository Instructions",
            text: sections.joined(separator: "\n\n"))
    }

    private func readCached(_ url: URL) -> String? {
        let mtime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        if let hit = cache[url.path], hit.mtime == mtime { return hit.text }
        guard let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8)
        else { return nil }
        let capped =
            raw.count > perFileCharCap
            ? String(raw.prefix(perFileCharCap)) + Self.truncationMarker
            : raw
        cache[url.path] = CacheEntry(mtime: mtime, text: capped)
        return capped
    }
}
