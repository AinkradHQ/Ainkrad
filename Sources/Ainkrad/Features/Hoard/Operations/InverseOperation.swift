import Foundation

/// An item that moved, recorded so it can be moved back.
struct MovedItem: Codable, Equatable, Sendable {
    var from: URL
    var to: URL
}

/// An item in the Trash, and where it came from.
struct TrashedItem: Codable, Equatable, Sendable {
    var original: URL
    var inTrash: URL
}

/// What undoing an operation actually does.
///
/// `.composite` exists because the two genuinely awkward cases — overwrite and
/// cross-volume move — are each TWO undos that must both happen: remove what
/// was written, and put back what was displaced. Modelling them as one action
/// each would either leave the new file behind or fail to restore the old one.
indirect enum InverseAction: Codable, Equatable, Sendable {
    case moveBack([MovedItem])
    case delete([URL])
    case restoreFromTrash([TrashedItem])
    case composite([InverseAction])
}

/// Enough to RE-RUN the original operation.
///
/// Redo cannot be derived from the inverse: undoing a copy deletes the copies,
/// and "delete the copies" reversed is not "copy them again" — the sources are
/// nowhere in the inverse. So the forward intent is recorded alongside it.
/// Codable because the undo stack is persisted, and a redo that vanished on
/// relaunch would be worse than none.
struct RedoSpec: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case copy, move, rename, createFolder, trash, batchRename, archive, extract
    }
    var kind: Kind
    var sources: [URL]
    var destinationDirectory: URL?
    var name: String?
    /// Positional against `sources`, for `.batchRename`. Optional so a stack
    /// written before batch rename existed still decodes.
    var names: [String]?
    var policy: ConflictPolicy = .keepBoth
}

/// One undoable step: what to do, what it touches, and when it happened.
///
/// `recordedAt` is not decoration — undo refuses to auto-invert an entry whose
/// files have been modified since, and this is the timestamp that comparison
/// is made against.
struct InverseOperation: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    /// Reads as what the USER did ("Copy 3 items"), not as what undoing it
    /// will do — the undo affordance says "Undo <label>".
    var label: String
    var action: InverseAction
    var recordedAt: Date
    /// The paths whose state this entry depends on, for the
    /// externally-modified check.
    var affectedURLs: [URL]
    /// How to perform this operation AGAIN, for redo. Optional so decoding a
    /// stack written before this existed still works.
    var redo: RedoSpec?
}

extension InverseOperation {
    private static func itemLabel(_ verb: String, _ count: Int) -> String {
        "\(verb) \(count) item\(count == 1 ? "" : "s")"
    }

    /// Same-volume move: the inverse is simply the reverse move.
    static func forMove(items: [MovedItem], at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Move", items.count),
            action: .moveBack(items.map { MovedItem(from: $0.to, to: $0.from) }),
            recordedAt: now,
            affectedURLs: items.map(\.to),
            redo: RedoSpec(
                kind: .move, sources: items.map(\.from),
                destinationDirectory: items.first?.to.deletingLastPathComponent()))
    }

    /// Copy: delete what we created. The sources were never touched.
    static func forCopy(
        created: [URL], sources: [URL] = [],
        at now: Date = Date()
    ) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Copy", created.count),
            action: .delete(created),
            recordedAt: now,
            affectedURLs: created,
            redo: sources.isEmpty
                ? nil
                : RedoSpec(
                    kind: .copy, sources: sources,
                    destinationDirectory: created.first?.deletingLastPathComponent()))
    }

    /// Overwrite: the displaced file was trashed BEFORE the write, so undo
    /// removes the new file and restores the old one — in that order, since
    /// restoring first would collide with the file still occupying the path.
    static func forOverwrite(
        created: [URL], overwritten: [TrashedItem],
        sources: [URL] = [], at now: Date = Date()
    ) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Replace", created.count),
            action: .composite([.delete(created), .restoreFromTrash(overwritten)]),
            recordedAt: now,
            affectedURLs: created,
            redo: sources.isEmpty
                ? nil
                : RedoSpec(
                    kind: .copy, sources: sources,
                    destinationDirectory: created.first?.deletingLastPathComponent(),
                    policy: .replace))
    }

    /// Cross-volume move: implemented as copy-then-trash-source, so the
    /// inverse is delete-the-copies plus restore-the-sources.
    static func forCrossVolumeMove(
        created: [URL], trashedSources: [TrashedItem],
        at now: Date = Date()
    ) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Move", created.count),
            action: .composite([.delete(created), .restoreFromTrash(trashedSources)]),
            recordedAt: now,
            affectedURLs: created,
            redo: RedoSpec(
                kind: .move, sources: trashedSources.map(\.original),
                destinationDirectory: created.first?.deletingLastPathComponent()))
    }

    static func forTrash(items: [TrashedItem], at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Delete", items.count),
            action: .restoreFromTrash(items),
            recordedAt: now,
            affectedURLs: items.map(\.original),
            redo: RedoSpec(
                kind: .trash, sources: items.map(\.original),
                destinationDirectory: nil))
    }

    static func forRename(
        from original: URL, to renamed: URL,
        at now: Date = Date()
    ) -> InverseOperation {
        InverseOperation(
            label: "Rename",
            action: .moveBack([MovedItem(from: renamed, to: original)]),
            recordedAt: now,
            affectedURLs: [renamed],
            redo: RedoSpec(
                kind: .rename, sources: [original], destinationDirectory: nil,
                name: renamed.lastPathComponent))
    }

    /// A whole batch rename as ONE entry, so ⌘Z puts every name back at once.
    ///
    /// Structurally just a multi-item `.moveBack` — which is safe here only
    /// because the planner blocks any row whose new name is already taken, so a
    /// batch can never contain a swap (a→b, b→a) whose reversal would collide
    /// mid-flight.
    static func forBatchRename(items: [MovedItem], at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Rename", items.count),
            action: .moveBack(items.map { MovedItem(from: $0.to, to: $0.from) }),
            recordedAt: now,
            affectedURLs: items.map(\.to),
            redo: RedoSpec(
                kind: .batchRename, sources: items.map(\.from),
                destinationDirectory: nil, name: nil,
                names: items.map { $0.to.lastPathComponent }))
    }

    /// Archive create and extract share an inverse: delete what was produced.
    /// The inputs are untouched by either, so nothing needs restoring.
    static func forArchive(
        created: [URL], sources: [URL], name: String,
        at now: Date = Date()
    ) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Compress", sources.count),
            action: .delete(created),
            recordedAt: now,
            affectedURLs: created,
            redo: RedoSpec(
                kind: .archive, sources: sources,
                destinationDirectory: created.first?.deletingLastPathComponent(),
                name: name))
    }

    static func forExtract(
        created: [URL], archives: [URL],
        into directory: URL, at now: Date = Date()
    ) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Extract", archives.count),
            action: .delete(created),
            recordedAt: now,
            affectedURLs: created,
            redo: RedoSpec(
                kind: .extract, sources: archives,
                destinationDirectory: directory))
    }

    static func forCreateFolder(at url: URL, now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: "New folder",
            action: .delete([url]),
            recordedAt: now,
            affectedURLs: [url],
            redo: RedoSpec(
                kind: .createFolder, sources: [],
                destinationDirectory: url.deletingLastPathComponent(),
                name: url.lastPathComponent))
    }
}
