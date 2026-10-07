import Foundation

/// Resolves the on-disk layout for custom commands:
///   <userRoot>/<name>.md               global (app-managed, all workspaces)
///   <workspace>/.ainkrad/commands/*.md  project-scoped (checked into the repo)
/// `projectRoot` is nil when there is no active workspace folder. `userRoot` is
/// always supplied by the caller — bootstrap derives it from the resolved `Home`
/// (`shared(.commands)`), tests from a per-test temp dir. There is deliberately
/// no default user root: this type cannot compute a storage path.
struct CustomCommandPaths {
    let userRoot: URL
    let projectRoot: URL?

    init(userRoot: URL, projectRoot: URL?) {
        self.userRoot = userRoot
        self.projectRoot = projectRoot
    }

    /// Every `*.md` under each root, tagged with its scope, sorted by filename
    /// per root for deterministic ordering. A missing directory yields no files
    /// (never an error), matching `SkillRegistry.installedDirNames()`.
    func commandFiles(fileManager: FileManager = .default) -> [(url: URL, scope: CustomCommand.Scope)] {
        var out: [(url: URL, scope: CustomCommand.Scope)] = []
        for (root, scope) in [(userRoot, CustomCommand.Scope.user)]
            + (projectRoot.map { [($0, CustomCommand.Scope.project)] } ?? [])
        {
            let entries =
                (try? fileManager.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil)) ?? []
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension.lowercased() == "md" {
                out.append((url, scope))
            }
        }
        return out
    }

    static func projectRoot(forWorkspace workspace: URL) -> URL {
        workspace.appendingPathComponent(".ainkrad", isDirectory: true)
            .appendingPathComponent("commands", isDirectory: true)
    }
}
