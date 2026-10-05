import Foundation

/// Running `git`. Behind a protocol so the parser and the provider are
/// testable against canned output — spawning a real process per test would be
/// slow, and would need a real repo fixture per case.
protocol GitRunning: Sendable {
    /// Runs `git <args>` with `directory` as the working directory and returns
    /// stdout. Throws on a non-zero exit or a launch failure.
    func run(_ args: [String], in directory: URL) throws -> String
}

struct GitRunFailure: Error {
    let status: Int32
    let stderr: String
}

/// `Process`-backed runner.
///
/// Shelling out rather than linking libgit2 is a deliberate trade: the host has
/// no git support today, and a C dependency is a large cost for status badges.
/// The price is a process spawn per repo per invalidation, which is why
/// `GitStatusProvider` caches per repo rather than per directory.
struct SystemGitRunner: GitRunning {
    func run(_ args: [String], in directory: URL) throws -> String {
        let process = Process()
        // `/usr/bin/env` so this follows the user's PATH rather than assuming
        // Xcode's git or a Homebrew location.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = directory

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        // Keep git non-interactive: a repo needing credentials must fail fast
        // rather than block the app on a prompt nobody can answer.
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"]) { _, new in new }

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GitRunFailure(
                status: process.terminationStatus,
                stderr: String(decoding: errorData, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Walks up from `directory` looking for a `.git` entry.
///
/// `.git` may be a FILE, not a directory — that is how worktrees and submodules
/// point at their real git dir — so this checks for existence, not
/// directory-ness. Stops at the filesystem root rather than looping forever.
func discoverRepositoryRoot(for directory: URL, fileSystem: any FileSystemServing) -> URL? {
    var candidate = URL(fileURLWithPath: directory.standardizedFileURL.path)
    while true {
        if fileSystem.exists(candidate.appendingPathComponent(".git")) {
            return candidate
        }
        let parent = candidate.deletingLastPathComponent()
        // `deletingLastPathComponent` on "/" returns "/" — the loop's exit.
        guard parent.path != candidate.path else { return nil }
        candidate = URL(fileURLWithPath: parent.path)
    }
}
