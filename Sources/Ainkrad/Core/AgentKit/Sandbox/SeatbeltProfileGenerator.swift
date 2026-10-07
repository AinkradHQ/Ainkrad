import Foundation

/// Generates a deny-by-default macOS sandbox profile (SBPL) from a filesystem +
/// network policy. Pure/text-only — no spawning, no filesystem access — so it
/// is fully unit-tested. Security invariant: the output MUST start from
/// `(deny default)` and grant only what the policy explicitly lists; a path
/// not present in the policy must never appear, in any form, in the output.
enum SeatbeltProfileGenerator {
    /// System read paths a spawned shell/process needs just to start (dyld,
    /// shared libs, /dev/null, etc). This is the ONLY implicit grant beyond
    /// what the policy lists — kept minimal and centralized for review.
    ///
    /// confirm at execution: this set drifts by macOS version — single edit
    /// point; validate against the target macOS before Task 6 wires up
    /// `sandbox-exec` against real processes.
    static let systemReadPaths = [
        "/usr", "/bin", "/sbin", "/System", "/Library",
        "/private/etc",  // zsh/bash global rc files (symlinked)
        "/private/var/select", "/private/var/db/dyld",
        "/dev/null", "/dev/urandom",
    ]

    /// Resolves the `<workspace>` placeholder and validates a policy path is
    /// safe to embed in generated SBPL. Fail-closed: anything that isn't an
    /// unambiguous absolute path is rejected rather than guessed at.
    private static func resolve(_ path: String, workspacePath: String) throws -> String {
        let expanded = path == "<workspace>" ? workspacePath : path
        guard !expanded.isEmpty, expanded.hasPrefix("/") else {
            throw BackendError.profileGeneration("Unresolvable sandbox path: \(path)")
        }
        // Reject control characters (newline, CR, NUL, etc). A raw newline
        // embedded in a quoted SBPL string literal is exploitable — it can be
        // used to break out of the literal into a new top-level s-expression
        // depending on parser leniency, and callers have no legitimate reason
        // to pass a path containing one. Fail closed instead of guessing.
        guard !expanded.unicodeScalars.contains(where: { $0.isASCII && $0.value < 0x20 }) else {
            throw BackendError.profileGeneration("Path contains control characters: \(path)")
        }
        return expanded
    }

    /// Escapes a resolved path for embedding inside an SBPL string literal.
    /// Backslash must be escaped first so a source `\"` doesn't get double
    /// counted as an already-escaped quote.
    private static func escapeLiteral(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Builds one `(allow <op> (subpath "..."))` line for a resolved path.
    private static func subpathRule(_ op: String, _ resolvedPath: String) -> String {
        "(allow \(op) (subpath \"\(escapeLiteral(resolvedPath))\"))"
    }

    static func generate(
        fs: FilesystemPolicy, network: NetworkPolicy,
        workspacePath: String
    ) throws -> String {
        var lines: [String] = [
            "(version 1)",
            "(deny default)",
            "(allow process-fork)",
            "(allow process-exec)",
            "(allow sysctl-read)",
            "(allow mach-lookup)",
            // Root directory itself (NOT subpath — this does not grant access
            // to anything under it) must be readable: dyld/zsh path
            // resolution (getcwd-style traversal, shared-cache lookup) stats
            // "/" during startup even when cwd is elsewhere. Without this a
            // sandboxed shell aborts (SIGABRT) before running anything.
            // confirmed at execution (Task 6): verified via `sandbox-exec`
            // denial log (`file-read-data /`) on the target macOS version.
            "(allow file-read-data (literal \"/\"))",
            "(allow file-read-metadata (literal \"/\"))",
        ]

        for sys in systemReadPaths {
            lines.append(subpathRule("file-read*", sys))
        }

        for r in fs.readablePaths {
            let resolved = try resolve(r, workspacePath: workspacePath)
            lines.append(subpathRule("file-read*", resolved))
        }

        for w in fs.writablePaths {
            let resolved = try resolve(w, workspacePath: workspacePath)
            lines.append(subpathRule("file-read*", resolved))
            lines.append(subpathRule("file-write*", resolved))
        }

        switch network {
        case .off:
            lines.append("(deny network*)")
        case .on:
            lines.append("(allow network*)")
        case .allowList:
            // SBPL has no hostname/domain primitive — it can only allow or deny
            // network* wholesale. An allow-list therefore cannot be enforced at
            // this layer; fail closed (deny) here rather than silently widen to
            // full network access. Hostname filtering belongs to a higher layer
            // (e.g. an egress proxy) that does not exist yet.
            // confirm at execution: revisit if/when that layer lands.
            lines.append("(deny network*)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
