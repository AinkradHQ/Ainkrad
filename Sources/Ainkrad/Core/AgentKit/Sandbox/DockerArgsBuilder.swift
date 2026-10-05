// Sources/Ainkrad/Core/AgentKit/Sandbox/DockerArgsBuilder.swift
import Foundation

/// Pure builder for `docker run` argv. Mirrors the security posture of
/// `SeatbeltProfileGenerator`: ONLY paths explicitly listed in the profile's
/// `FilesystemPolicy` are mounted — readable paths read-only, writable paths
/// read-write. A path not present in the policy is never mounted, in any form.
///
/// argv is built as a `[String]`, never a shell-joined string, so a
/// path/command containing shell metacharacters can't inject an extra docker
/// flag or escape its argv slot — `Process`/docker parse each element
/// verbatim, with no shell re-tokenization step.
enum DockerArgsBuilder {
    static func runArgs(
        command: String, profile: SandboxProfile,
        workspacePath: String, image: String
    ) -> [String] {
        var args: [String] = ["run", "--rm"]

        switch profile.networkPolicy {
        case .off:
            args += ["--network", "none"]
        case .on:
            args += ["--network", "bridge"]
        case .allowList:
            // Docker has no per-hostname allow-list primitive comparable to an
            // egress proxy, so it can't honor "restrict to these hosts" —
            // and silently degrading that to full bridge network would be
            // fail-OPEN. Fail CLOSED instead: deny all network, matching
            // SeatbeltProfileGenerator's posture for this same
            // un-filterable case.
            args += ["--network", "none"]
        }

        if let mem = profile.resourceLimits.memoryMB { args += ["--memory", "\(mem)m"] }
        if let cpu = profile.resourceLimits.cpuCount { args += ["--cpus", "\(cpu)"] }

        // Writable paths win if a path is (unusually) listed in both sets —
        // mount once, read-write, never duplicated as also read-only.
        var writableResolved = Set<String>()
        for w in profile.fsPolicy.writablePaths {
            guard let resolved = resolvedPath(w, workspacePath: workspacePath) else { continue }
            writableResolved.insert(resolved)
            args += ["-v", "\(resolved):\(resolved)"]
        }
        for r in profile.fsPolicy.readablePaths {
            guard let resolved = resolvedPath(r, workspacePath: workspacePath) else { continue }
            guard !writableResolved.contains(resolved) else { continue }
            args += ["-v", "\(resolved):\(resolved):ro"]
        }

        args += ["-w", workspacePath]
        args += [image, "zsh", "-lc", command]
        return args
    }

    /// Resolves the `<workspace>` placeholder and validates a policy path is
    /// safe to embed as a bind-mount source. Fail-closed: anything that isn't
    /// an unambiguous absolute path (or contains control characters, or a
    /// `:` that would collide with docker's `-v source:dest:mode` separator
    /// and produce a malformed/misinterpreted mount) is rejected — silently
    /// skipped from the mount list — rather than guessed at or passed
    /// through. Mirrors `SeatbeltProfileGenerator.resolve`.
    private static func resolvedPath(_ path: String, workspacePath: String) -> String? {
        let expanded = path == "<workspace>" ? workspacePath : path
        guard !expanded.isEmpty, expanded.hasPrefix("/") else { return nil }
        guard !expanded.unicodeScalars.contains(where: { $0.isASCII && $0.value < 0x20 }) else { return nil }
        guard !expanded.contains(":") else { return nil }
        return expanded
    }
}
