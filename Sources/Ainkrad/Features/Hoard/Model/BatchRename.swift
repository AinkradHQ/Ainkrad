import Foundation

/// One planned rename, for the preview table.
struct BatchRenamePlanItem: Identifiable, Equatable, Sendable {
    var entry: FileEntry
    var newName: String
    /// Why this row will not be applied, if it won't.
    var problem: Problem?

    var id: URL { entry.url }
    var isChanged: Bool { newName != entry.name && problem == nil }

    enum Problem: Equatable, Sendable {
        case unchanged
        case emptyResult
        case collidesWithExisting
        case collidesWithAnotherRename
    }
}

/// The one-line verdict on a plan, for the sheet's footer.
///
/// Counted rather than inferred at the call site, because "how many will
/// actually change" is the number the Apply button depends on and getting it
/// subtly wrong is how a batch rename surprises you.
struct BatchRenameSummary: Equatable, Sendable {
    var willRename = 0
    var blocked = 0
    var unchanged = 0

    /// Blocked rows do NOT disable the button — they are skipped, and the
    /// footer says how many. Refusing the whole batch over one collision
    /// would mean re-deriving a pattern that is right for the other 200.
    var canApply: Bool { willRename > 0 }
}

extension Array where Element == BatchRenamePlanItem {
    var renameSummary: BatchRenameSummary {
        var summary = BatchRenameSummary()
        for item in self {
            switch item.problem {
            case nil: summary.willRename += 1
            case .unchanged: summary.unchanged += 1
            default: summary.blocked += 1
            }
        }
        return summary
    }
}

enum BatchRenameMode: String, CaseIterable, Sendable {
    case findReplace
    case addPrefix
    case addSuffix
    case numberSequentially
}

/// Computes the full plan BEFORE anything is applied.
///
/// A preview is not a nicety here: batch rename is the highest-leverage and
/// highest-blast-radius operation in the app, and the failure mode is renaming
/// 400 files correctly-but-wrongly. Seeing the result first is the difference
/// between confidence and an undo scramble.
///
/// Collisions are detected in BOTH directions — against files already on disk,
/// and against other rows in the same batch, which is the case a naive
/// implementation misses and which silently destroys data.
func batchRenamePlan(
    entries: [FileEntry], mode: BatchRenameMode,
    find: String, replace: String,
    existingNames: Set<String>,
    startNumber: Int = 1
) -> [BatchRenamePlanItem] {
    var plan: [BatchRenamePlanItem] = []
    var claimed: Set<String> = []

    for (offset, entry) in entries.enumerated() {
        let newName = renamedName(
            entry: entry, mode: mode, find: find,
            replace: replace, index: startNumber + offset)

        var problem: BatchRenamePlanItem.Problem?
        if newName.isEmpty {
            problem = .emptyResult
        } else if newName == entry.name {
            problem = .unchanged
        } else if claimed.contains(newName) {
            problem = .collidesWithAnotherRename
        } else if existingNames.contains(newName) && newName != entry.name {
            problem = .collidesWithExisting
        }

        if problem == nil { claimed.insert(newName) }
        plan.append(BatchRenamePlanItem(entry: entry, newName: newName, problem: problem))
    }
    return plan
}

private func renamedName(
    entry: FileEntry, mode: BatchRenameMode,
    find: String, replace: String, index: Int
) -> String {
    let name = entry.name
    switch mode {
    case .findReplace:
        guard !find.isEmpty else { return name }
        return name.replacingOccurrences(of: find, with: replace)

    case .addPrefix:
        return replace + name

    case .addSuffix:
        // Before the extension, not after it — "photo.jpg" + "-edited" must
        // give "photo-edited.jpg", not "photo.jpg-edited".
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        return ext.isEmpty ? stem + replace : "\(stem)\(replace).\(ext)"

    case .numberSequentially:
        let ext = (name as NSString).pathExtension
        let base = replace.isEmpty ? (name as NSString).deletingPathExtension : replace
        let numbered = "\(base) \(index)"
        return ext.isEmpty ? numbered : "\(numbered).\(ext)"
    }
}
