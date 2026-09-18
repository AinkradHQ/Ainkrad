import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The Hoard pane: sidebar beside a column of tab strip, breadcrumb, list and
/// status bar. Composition only — no behaviour lives here.
///
/// Deliberately paints NO background of its own. The pane's fill comes from
/// `HoardApp.surfaceFill` via `RegisteredApp.chromeFill`, which is what lets a
/// translucent Hoard reveal the shared blurred island and keeps the title bar
/// the same colour and opacity as the body. Any opaque background here would
/// cover the island and break that continuity.
struct HoardRootView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var store: HoardPaneStore?
    @State private var actions: HoardActions?
    @State private var paneToken: UUID?
    @State private var resolver = ConflictResolver()
    /// Which mode this pane is in. An input rather than an environment read
    /// because the whole view is built for it — see `columns(store:actions:)`.
    var mode: PluginMode = .advanced

    @State private var isEditingPath = false
    @State private var watcher: DirectoryWatcher?
    @State private var toast: HoardToastMessage?
    /// Per-item failure reasons, shown when the summary's "Details" is tapped.
    @State private var failureDetails: [OperationFailure] = []
    @State private var search: HoardSearchStore?
    /// The pane's ONE focus state, shared by the list and the search field.
    @FocusState private var focus: HoardFocusTarget?

    private var settings: HoardSettingsStore { environment.filesSettingsStore }
    private var fileSystem: LocalFileSystemService { environment.filesSystemService }
    private var engine: FileOperationEngine { environment.filesOperationEngine }
    private var git: GitStatusProvider { environment.filesGitStatusProvider }

    var body: some View {
        Group {
            if let store, let actions {
                paneBody(store: store, actions: actions)
            } else {
                AinkradLoadingState(label: "Opening…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .filesTypography(environment)
        .task { activate() }
        .onDisappear(perform: deactivate)
    }

    private func paneBody(store: HoardPaneStore, actions: HoardActions) -> some View {
        HStack(spacing: 0) {
            // Basic mode is ONE directory: no sidebar, no tabs, no filter, no
            // preview. The sidebar is not merely hidden — building it
            // enumerates the pinned roots AND every known git repository root,
            // and the preview renders the cursor's file with syntax
            // highlighting. Neither runs here.
            if mode != .basic {
                HoardSidebar(
                    sections: sidebarSections(
                        home: fileSystem.homeDirectory,
                        pinned: environment.filesPinnedRoots.roots,
                        repositories: git.knownRepositoryRoots),
                    currentDirectory: store.activeTab.currentDirectory,
                    iconSize: CGFloat(settings.iconSize),
                    rowPadding: settings.rowVerticalPadding,
                    onSelect: { store.activeTab.navigate(to: $0.url) },
                    onRemove: { environment.filesPinnedRoots.unpin($0.url) }
                )
            }
            VStack(spacing: 0) {
                if mode != .basic { HoardTabStrip(store: store) }
                HStack(spacing: AinkradSpacing.sm) {
                    HoardBreadcrumbBar(tab: store.activeTab, fileSystem: fileSystem,
                                       isEditing: $isEditingPath)
                    if mode == .basic {
                        Spacer(minLength: AinkradSpacing.sm)
                        // The way out. Hoard's header is its breadcrumb, so the
                        // switch rides there rather than in a shell this view
                        // does not use.
                        AinkradModeSwitch()
                            .padding(.trailing, HoardColumnMetrics.headerInset)
                    } else if let search {
                        HoardFilterField(search: search, focus: $focus)
                            .padding(.trailing, HoardColumnMetrics.headerInset)
                    }
                }
                FileListView(
                    tab: store.activeTab,
                    iconSize: CGFloat(settings.iconSize),
                    rowPadding: settings.rowVerticalPadding,
                    showMetadata: settings.showMetadataColumns,
                    searchHits: (search?.isScoped ?? false) ? (search?.scopedResults ?? []) : nil,
                    isSearching: search?.isScopedSearching ?? false,
                    useGrid: settings.useGrid,
                    gitStatus: { git.status(for: $0) },
                    isCut: { environment.filesClipboard.isCut($0) },
                    menuActions: rowMenu(store: store, actions: actions),
                    onOpenHit: { hit in accept(hit, store: store) }
                )
                HoardStatusBar(
                    tab: store.activeTab,
                    repoStatus: git.status(forDirectory: store.activeTab.currentDirectory))
            }
            if settings.showPreview && mode != .basic {
                PreviewPane(entry: store.activeTab.cursorEntry,
                            itemCount: store.activeTab.visibleEntries.count)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: settings.showPreview)
        .filesKeyboardHandling(
            store: store, actions: actions, undoStack: environment.filesUndoStack,
            onUndo: {
                if let refusal = engine.undo() {
                    toast = HoardToastMessage(kind: .warning, text: "Can't undo that",
                                              detail: refusal.message)
                } else {
                    toast = HoardToastMessage(kind: .undone, text: "Undone",
                                              detail: "⌘⇧Z to redo")
                }
            },
            onRedo: {
                Task {
                    _ = await engine.redo()
                    store.activeTab.reload()
                    toast = HoardToastMessage(kind: .undone, text: "Redone", detail: "⌘Z to undo")
                }
            },
            onTogglePreview: { settings.showPreview.toggle() },
            onOpenFinder: { mode in openFinder(mode, store: store) },
            onFocusFilter: {
                let searchStore = ensureSearch()
                searchStore.scopedRoot = self.store?.activeTab.currentDirectory
                focus = .search
            },
            onTogglePin: {
                let directory = store.activeTab.currentDirectory
                let pins = environment.filesPinnedRoots
                let wasPinned = pins.isPinned(directory)
                pins.toggle(directory)
                // Say which way it went: a star appearing in a sidebar the eye
                // isn't on reads as nothing happening.
                toast = HoardToastMessage(
                    kind: wasPinned ? .undone : .created,
                    text: wasPinned ? "Removed from Favourites" : "Added to Favourites",
                    detail: directory.lastPathComponent)
            },
            isFinderOpen: search?.isActive ?? false,
            vimKeys: settings.vimKeys,
            focus: $focus,
            isEditingPath: $isEditingPath)
        .overlay(alignment: .top) {
            if let search, search.isActive {
                HoardFinderBar(
                    search: search,
                    iconSize: CGFloat(settings.iconSize),
                    onSubmit: { hit in accept(hit, store: store) },
                    onClose: { search.close() })
                    .padding(.top, AinkradSpacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            // ⌘⇧F rides an AppKit local monitor, not `.onKeyPress` — see
            // `HoardKeyMonitor` for why. Zero-size and invisible; it lives as
            // long as the pane does.
            HoardKeyMonitor(chords: [
                HoardOptionChord(keyCode: HoardOptionChord.f) {
                    let searchStore = ensureSearch()
                    searchStore.scopedRoot = store.activeTab.currentDirectory
                    // Set the shared focus target directly — no request counter,
                    // no second focus state to lose a race with.
                    focus = .search
                },
                // ⌥R, ⌥A and ⌥E ride the same monitor for the same reason ⌥F
                // does: they must work whether the caret is in the list, the
                // breadcrumb or the search field.
                HoardOptionChord(keyCode: HoardOptionChord.r) { actions.beginBatchRename() },
                HoardOptionChord(keyCode: HoardOptionChord.a) {
                    Task { await actions.archiveSelection() }
                },
                HoardOptionChord(keyCode: HoardOptionChord.e) {
                    Task { await actions.extractSelection() }
                }
            ])
            .frame(width: 0, height: 0)
        )
        .overlay(alignment: .bottomTrailing) {
            OperationsPanel(engine: engine).padding(AinkradSpacing.md)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                HoardToast(
                    message: toast,
                    onDismiss: { self.toast = nil },
                    onShowDetails: { failureDetails = toast.failures })
                    .padding(.bottom, AinkradSpacing.lg)
                    .task(id: toast.id) {
                        // Auto-dismiss successes; a confirmation that lingers
                        // becomes clutter you learn to ignore. FAILURES stay
                        // until dismissed — auto-hiding them would take the
                        // only route to the per-item reasons with it.
                        guard !toast.kind.isProblem else { return }
                        try? await Task.sleep(for: .seconds(3))
                        if self.toast?.id == toast.id { self.toast = nil }
                    }
            }
        }
        // One watcher, always pointed at whatever the active tab is showing.
        .onChange(of: store.activeTab.currentDirectory, initial: true) { _, directory in
            watcher?.stop()
            watcher = DirectoryWatcher(url: directory) { [weak store] in
                store?.activeTab.reload()
                // The watcher's 200ms coalescing is what keeps a `git checkout`
                // from spawning hundreds of status refreshes.
                Task { await refreshGit(directory: directory, store: store) }
            }
            Task { await refreshGit(directory: directory, store: store) }
        }
        // The coordinator needs to know which pane was last touched, so F5 in
        // a three-pane workspace targets the one the user actually means.
        .onTapGesture {
            if let paneToken { environment.filesPaneCoordinator.noteFocus(paneToken) }
        }
        .onChange(of: actions.lastToast) { _, message in
            if let message { toast = message; actions.clearMessage() }
        }
        // The scoped search follows the pane as it navigates.
        .onChange(of: store.activeTab.currentDirectory, initial: true) { _, directory in
            search?.scopedRoot = directory
        }
        .sheet(item: Binding(get: { actions.prompt },
                             set: { if $0 == nil { actions.present(nil) } })) { prompt in
            HoardPromptSheet(
                prompt: prompt,
                onCancel: { actions.present(nil) },
                onRename: { entry, name in Task { await actions.commitRename(entry, to: name) } },
                onNewFolder: { name in Task { await actions.commitNewFolder(named: name) } })
        }
        .sheet(isPresented: Binding(get: { actions.batchRenameTargets != nil },
                                    set: { if !$0 { actions.cancelBatchRename() } })) {
            if let targets = actions.batchRenameTargets {
                BatchRenameSheet(
                    entries: targets,
                    siblings: actions.batchRenameSiblings,
                    onCancel: { actions.cancelBatchRename() },
                    onApply: { plan in Task { await actions.commitBatchRename(plan) } })
            }
        }
        .sheet(isPresented: Binding(get: { !failureDetails.isEmpty },
                                    set: { if !$0 { failureDetails = [] } })) {
            HoardFailureSheet(failures: failureDetails) { failureDetails = [] }
        }
        .sheet(isPresented: Binding(get: { resolver.pending != nil },
                                    set: { if !$0 { resolver.cancel() } })) {
            if let question = resolver.pending {
                ConflictSheet(question: question) { resolver.answer($0) }
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
    }

    /// The right-click menu's wiring. Everything here already exists as a
    /// keyboard chord — this is the discoverable path to the same actions,
    /// which the app had none of until now.
    private func rowMenu(store: HoardPaneStore, actions: HoardActions) -> FileRowMenuActions {
        let pins = environment.filesPinnedRoots
        return FileRowMenuActions(
            open: { store.activeTab.descend(into: $0) },
            rename: { actions.beginRename($0) },
            copy: { actions.copySelection() },
            cut: { actions.cutSelection() },
            paste: { Task { await actions.paste() } },
            compress: { Task { await actions.archiveSelection() } },
            extractArchives: { Task { await actions.extractSelection() } },
            trash: { Task { await actions.trashSelection() } },
            togglePin: { pins.toggle($0.url) },
            canExtract: { SystemArchiveService().canExtract($0.url) },
            isPinned: { pins.isPinned($0.url) })
    }

    /// `/` and ⌘P work off data already in memory; ⌘F walks the disk, so it
    /// only starts when the user commits with Return.
    @discardableResult
    private func ensureSearch() -> HoardSearchStore {
        if let search { return search }
        let created = HoardSearchStore(fileSystem: fileSystem)
        search = created
        return created
    }

    private func openFinder(_ mode: HoardFinderMode, store: HoardPaneStore) {
        // ⌘F is GLOBAL: rooted at home, not at whatever folder the pane is
        // showing. ⌘P jumps within the current tree, where "nearby" is the
        // point.
        let root = mode == .globalSearch
            ? fileSystem.homeDirectory
            : store.activeTab.currentDirectory
        ensureSearch().open(mode, root: root)
    }

    private func accept(_ hit: SearchHit, store: HoardPaneStore) {
        let tab = store.activeTab
        if hit.entry.isDirectory {
            tab.navigate(to: hit.entry.url)
        } else {
            tab.navigate(to: hit.entry.url.deletingLastPathComponent())
            tab.select(matching: hit.entry.url)
        }
        search?.close()
    }

    private func activate() {
        guard store == nil else { return }
        let store = HoardPaneStore(fileSystem: fileSystem, persistence: environment.persistence)
        let token = environment.filesPaneCoordinator.register(store)
        self.store = store
        self.paneToken = token
        // Enter on a markdown file hands it to Lore. Wired here rather than in
        // the store because only the pane can reach the host's launcher, and
        // only the host knows whether Lore is installed at all.
        store.activeTab.onOpenDocument = { [weak environment] url in
            guard let reason = environment?.openDocumentInLore(url) else { return }
            // Surfaced, not logged. Pressing Enter and getting nothing, with
            // only a log line to say why, is the failure this codebase has been
            // bitten by before.
            toast = HoardToastMessage(kind: .warning, text: "Can't open that", detail: reason)
        }
        self.actions = HoardActions(
            engine: engine, coordinator: environment.filesPaneCoordinator,
            resolver: resolver, clipboard: environment.filesClipboard,
            store: store, paneToken: token)
        ensureSearch()
    }

    /// Fetches status if cold, then republishes the ignore set so the list can
    /// filter on it.
    private func refreshGit(directory: URL, store: HoardPaneStore?) async {
        await git.refreshIfNeeded(directory: directory)
        guard let store, let status = git.status(forDirectory: directory) else {
            store?.activeTab.ignoredURLs = []
            return
        }
        let ignored = status.entries
            .filter { $0.value == .ignored }
            .map { status.root.appendingPathComponent($0.key) }
        store.activeTab.ignoredURLs = Set(ignored)
    }

    private func deactivate() {
        watcher?.stop()
        watcher = nil
        // Deregister so a closed pane stops being a copy target. The
        // coordinator lives in `AppEnvironment` precisely so this is safe —
        // the surviving pane is unaffected.
        if let paneToken { environment.filesPaneCoordinator.deregister(paneToken) }
        paneToken = nil
    }
}
