import Foundation

/// Decides whether an assistant-initiated operation is allowed to touch a path.
///
/// The rule from the spec: mutation tools refuse to operate outside the panes'
/// current roots unless the caller passes an explicit absolute path. An
/// assistant that misreads "clean up these files" must fail CLOSED rather than
/// recursing from `/`.
///
/// Pure and value-based so every branch is testable without a pane, a model,
/// or a filesystem.
enum HoardToolScope {
    /// Paths that are never acceptable targets regardless of how explicit the
    /// caller was. These are not "outside the roots" — they are places where a
    /// mistake is unrecoverable or breaks the machine.
    static let forbiddenRoots: [String] = ["/System", "/Library", "/bin", "/sbin", "/usr", "/private/var/db"]

    enum Decision: Equatable {
        case allowed
        case refused(reason: String)
    }

    /// - Parameters:
    ///   - target: the path the tool wants to act on.
    ///   - openRoots: the directories currently open in Hoard panes.
    ///   - wasExplicitlyAbsolute: true when the CALLER supplied a fully
    ///     qualified path rather than a name resolved against a pane. An
    ///     explicit path is a deliberate act; a resolved name is an inference,
    ///     and inference is what goes wrong.
    static func decide(
        target: URL, openRoots: [URL],
        wasExplicitlyAbsolute: Bool
    ) -> Decision {
        let path = target.standardizedFileURL.path

        // `..` that escapes upward is a traversal attempt, not a path.
        if target.pathComponents.contains("..") {
            return .refused(reason: "Path contains “..” — resolve it before calling.")
        }

        for forbidden in forbiddenRoots where path == forbidden || path.hasPrefix(forbidden + "/") {
            return .refused(reason: "“\(forbidden)” is off limits to file tools.")
        }

        // The root itself, and a bare home, are too broad to be a target even
        // when spelled out — the blast radius is the whole machine.
        if path == "/" {
            return .refused(reason: "Refusing to operate on the filesystem root.")
        }

        if isInside(path, anyOf: openRoots) { return .allowed }

        if wasExplicitlyAbsolute { return .allowed }

        return .refused(
            reason: """
                “\(path)” is outside every open Hoard pane. Pass a full absolute path \
                if you meant to reach outside.
                """)
    }

    static func isInside(_ path: String, anyOf roots: [URL]) -> Bool {
        roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}
