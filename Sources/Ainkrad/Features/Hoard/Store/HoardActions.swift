import Foundation
import Observation

/// What the pane is currently asking the user for.
enum HoardPrompt: Identifiable {
    case rename(FileEntry)
    case newFolder
    /// Copy or move with nowhere to send it — only one Hoard pane is open.
    case noDestination(isMove: Bool)

    var id: String {
        switch self {
        case .rename(let entry): return "rename-\(entry.url.path)"
        case .newFolder: return "new-folder"
        case .noDestination(let isMove): return "no-destination-\(isMove)"
        }
    }
}

/// Turns a pane's selection into `FileOperation`s and submits them.
///
/// Sits between the views and `FileOperationEngine` so the keyboard layer, the
/// context menu and (later) the assistant all go through ONE place that knows
/// how to read a selection, find the destination pane, and refresh afterwards.
@MainActor
@Observable
final class HoardActions {
    private let engine: FileOperationEngine
    private let coordinator: PaneCoordinator
    private let resolver: ConflictResolver
    private let clipboard: HoardClipboard
    private let store: HoardPaneStore
    private let paneToken: UUID

    private(set) var prompt: HoardPrompt?
    /// Last operation's user-facing result, surfaced as a toast.
    private(set) var lastToast: HoardToastMessage?

    init(
        engine: FileOperationEngine, coordinator: PaneCoordinator,
        resolver: ConflictResolver, clipboard: HoardClipboard,
        store: HoardPaneStore, paneToken: UUID
    ) {
        self.engine = engine
        self.coordinator = coordinator
        self.resolver = resolver
        self.clipboard = clipboard
        self.store = store
        self.paneToken = paneToken
    }

    private var tab: HoardTab { store.activeTab }

    /// The selection, or the cursor row when nothing is explicitly selected —
    /// so F5 with a cursor but no selection does the obvious thing instead of
    /// nothing.
    private var selectedEntries: [FileEntry] {
        if !tab.selection.isEmpty {
            return tab.visibleEntries.filter { tab.selection.contains($0.url) }
        }
        return tab.cursorEntry.map { [$0] } ?? []
    }

    private var operands: [URL] { selectedEntries.map(\.url) }

    func present(_ prompt: HoardPrompt?) { self.prompt = prompt }
    func clearMessage() { lastToast = nil }

    // MARK: - Clipboard
    //
    // The ordinary idiom, and the primary one. Cross-pane F5/F6 below remains
    // for orthodox-manager muscle memory, but it is no longer the only way to
    // move a file.

    func copySelection() {
        let sources = operands
        guard !sources.isEmpty else { return }
        clipboard.copy(sources)
        lastToast = HoardToastMessage(
            kind: .copied,
            text: "Copied \(sources.count) item\(sources.count == 1 ? "" : "s")",
            detail: "⌘V to paste")
    }

    func cutSelection() {
        let sources = operands
        guard !sources.isEmpty else { return }
        clipboard.cut(sources)
        lastToast = HoardToastMessage(
            kind: .cut,
            text: "Cut \(sources.count) item\(sources.count == 1 ? "" : "s")",
            detail: "⌘V to move them here")
    }

    /// Pastes into the CURRENT directory — so a single pane can copy from one
    /// folder to another, which the two-pane-only design could not do.
    func paste() async {
        guard let pending = clipboard.pendingOperation() else {
            lastToast = HoardToastMessage(kind: .warning, text: "Nothing to paste", detail: nil)
            return
        }
        let destination = tab.currentDirectory

        // Pasting into the folder the files already live in would be a no-op
        // for a move and a same-name conflict for a copy; keep-both makes the
        // copy case do the obviously-right thing.
        resolver.reset()
        let operation = FileOperation(
            kind: pending.isMove ? .move : .copy,
            sources: pending.urls,
            destinationDirectory: destination,
            policy: .ask)
        let result = await engine.submit(operation, conflictResolver: resolver.resolve)

        if pending.isMove, result.failures.isEmpty { clipboard.clearAfterMove() }
        report(result, verb: pending.isMove ? "Moved" : "Copied")
        tab.reload()
    }

    // MARK: - Cross-pane transfer

    func copyToOtherPane() async { await transfer(isMove: false) }
    func moveToOtherPane() async { await transfer(isMove: true) }

    private func transfer(isMove: Bool) async {
        let sources = operands
        guard !sources.isEmpty else { return }
        guard let destination = coordinator.otherPane(than: paneToken) else {
            // One pane open: say so rather than silently doing nothing.
            prompt = .noDestination(isMove: isMove)
            return
        }

        resolver.reset()
        let operation = FileOperation(
            kind: isMove ? .move : .copy, sources: sources,
            destinationDirectory: destination.activeTab.currentDirectory)
        let result = await engine.submit(operation, conflictResolver: resolver.resolve)

        report(result, verb: isMove ? "Moved" : "Copied")
        tab.reload()
        destination.activeTab.reload()
    }

    // MARK: - In-place operations

    func beginRename() {
        guard let entry = tab.cursorEntry else { return }
        prompt = .rename(entry)
    }

    /// Rename a specific row — what the context menu calls, since the row you
    /// right-clicked is the one you mean, cursor or not.
    func beginRename(_ entry: FileEntry) { prompt = .rename(entry) }

    func commitRename(_ entry: FileEntry, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.name else {
            prompt = nil
            return
        }
        let result = await engine.submit(
            FileOperation(
                kind: .rename(newName: trimmed), sources: [entry.url], destinationDirectory: nil))
        prompt = nil
        report(result, verb: "Renamed")
        tab.reload()
    }

    func beginNewFolder() { prompt = .newFolder }

    func commitNewFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            prompt = nil
            return
        }
        let result = await engine.submit(
            FileOperation(
                kind: .createFolder(name: trimmed), sources: [],
                destinationDirectory: tab.currentDirectory))
        prompt = nil
        report(result, verb: "Created")
        tab.reload()
    }

    // MARK: - Archives
    //
    // `ArchiveService` shipped in M5 with tests and no caller — it was reachable
    // from nothing. These are the wiring, and they go through the engine so
    // compressing is undoable like every other mutation.

    func archiveSelection() async {
        let sources = operands
        guard !sources.isEmpty else { return }
        let directory = tab.currentDirectory
        let result = await engine.submit(
            FileOperation(
                kind: .archive(name: defaultArchiveName(for: sources, in: directory)),
                sources: sources, destinationDirectory: directory))
        report(result, verb: "Compressed")
        tab.reload()
    }

    /// Extracts every selected archive into the current directory. Rows that
    /// are not archives are skipped rather than failed — selecting a folder
    /// and its zip and hitting extract should extract the zip.
    func extractSelection(using archiver: any Archiving = SystemArchiveService()) async {
        let archives =
            selectedEntries
            .filter { !$0.isDirectory && archiver.canExtract($0.url) }
            .map(\.url)
        guard !archives.isEmpty else {
            lastToast = HoardToastMessage(
                kind: .warning, text: "Nothing to extract",
                detail: "Select a .zip or .tar archive")
            return
        }
        let result = await engine.submit(
            FileOperation(
                kind: .extract, sources: archives, destinationDirectory: tab.currentDirectory))
        report(result, verb: "Extracted")
        tab.reload()
    }

    // MARK: - Batch rename

    /// The rows the batch-rename sheet is acting on, or nil while it is closed.
    private(set) var batchRenameTargets: [FileEntry]?
    /// Every name already in the folder — the other half of the collision
    /// check. Snapshotted when the sheet opens rather than read live, so the
    /// preview the user approved is the plan that gets applied.
    private(set) var batchRenameSiblings: Set<String> = []

    func beginBatchRename() {
        let targets = selectedEntries
        guard !targets.isEmpty else {
            lastToast = HoardToastMessage(
                kind: .warning, text: "Nothing selected",
                detail: "Select the files to rename first")
            return
        }
        batchRenameSiblings = Set(tab.entries.map(\.name))
        batchRenameTargets = targets
    }

    func cancelBatchRename() { batchRenameTargets = nil }

    /// Applies ONLY the clean rows. Rows the preview showed as blocked stay
    /// blocked — renaming them anyway after showing a warning is exactly the
    /// data loss the preview exists to prevent.
    ///
    /// ONE `.batchRename` operation, not a rename per row — so the whole batch
    /// is a single undo entry and ⌘Z puts every name back at once.
    func commitBatchRename(_ plan: [BatchRenamePlanItem]) async {
        batchRenameTargets = nil
        let applicable = plan.filter { $0.problem == nil }
        guard !applicable.isEmpty else { return }

        var result = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: applicable.map(\.newName)),
                sources: applicable.map(\.entry.url),
                destinationDirectory: nil))
        // Blocked rows were shown as blocked; count them as skipped so the
        // toast reports the batch honestly rather than only its clean half.
        result.skipped = plan.count - applicable.count

        report(result, verb: "Renamed")
        tab.reload()
    }

    func trashSelection() async {
        let sources = operands
        guard !sources.isEmpty else { return }
        let result = await engine.submit(
            FileOperation(
                kind: .trash, sources: sources, destinationDirectory: nil))
        report(result, verb: "Moved to Trash")
        tab.reload()
    }

    // MARK: - Reporting

    /// A one-line summary. Partial failure is reported honestly — "47 copied,
    /// 3 failed" — rather than a bare success that hides the three.
    private func report(_ result: OperationResult, verb: String) {
        guard result.succeeded > 0 || !result.failures.isEmpty || result.skipped > 0 else {
            lastToast = nil
            return
        }

        var detailParts: [String] = []
        if result.skipped > 0 { detailParts.append("\(result.skipped) skipped") }
        if result.wasCancelled { detailParts.append("cancelled") }

        if !result.failures.isEmpty {
            detailParts.append("\(result.failures.count) failed")
            lastToast = HoardToastMessage(
                kind: .failure,
                text: "\(verb) \(result.succeeded) item\(result.succeeded == 1 ? "" : "s")",
                detail: detailParts.joined(separator: " · "),
                // Carried so "3 failed" can be opened to WHICH three and why.
                failures: result.failures)
            return
        }

        // Success says it is reversible — the single most useful thing a
        // confirmation can tell you after a destructive-looking action.
        detailParts.append("⌘Z to undo")
        lastToast = HoardToastMessage(
            kind: kind(for: verb),
            text: "\(verb) \(result.succeeded) item\(result.succeeded == 1 ? "" : "s")",
            detail: detailParts.joined(separator: " · "))
    }

    private func kind(for verb: String) -> HoardToastKind {
        switch verb {
        case "Copied": return .copied
        case "Moved": return .moved
        case "Moved to Trash": return .deleted
        case "Created", "Compressed", "Extracted": return .created
        default: return .moved
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
