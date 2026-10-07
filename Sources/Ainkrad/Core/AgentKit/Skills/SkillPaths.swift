import AinkradHostRuntime
import Foundation

/// Resolves the on-disk layout for skills (global, app-managed):
///   Skills/<name>/SKILL.md            installed (marketplace) or local
///   Skills/_proposed/<name>/SKILL.md  agent-drafted, pending approval
///
/// `root` is always supplied by the caller — bootstrap derives it from the
/// resolved `Home` (`shared(.skills)`), tests from a per-test temp directory.
/// There is deliberately no default: this type cannot compute a storage path.
struct SkillPaths {
    let root: URL
    init(root: URL) { self.root = root }

    var proposedRoot: URL { root.appendingPathComponent("_proposed", isDirectory: true) }

    func skillDir(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    func skillFile(_ name: String) -> URL { skillDir(name).appendingPathComponent("SKILL.md") }
    func proposedDir(_ name: String) -> URL { proposedRoot.appendingPathComponent(name, isDirectory: true) }
    func proposedFile(_ name: String) -> URL { proposedDir(name).appendingPathComponent("SKILL.md") }

    /// Creates `root` and `proposedRoot` on disk if they don't already exist.
    /// Call once before first use (e.g. at skill-discovery startup); safe to
    /// call repeatedly.
    func ensureDirectoriesExist(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: proposedRoot, withIntermediateDirectories: true)
    }
}
