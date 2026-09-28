import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The sortable header + scrolling rows for one tab.
struct FileListView: View {
    @Bindable var tab: HoardTab
    let iconSize: CGFloat
    let rowPadding: CGFloat
    let showMetadata: Bool
    /// Scoped search results, when the in-pane field has something in it.
    /// `nil` means show the directory normally. A value — even empty — means
    /// the list is showing SEARCH results, so an empty array must read as "no
    /// matches" rather than "empty folder".
    let searchHits: [SearchHit]?
    let isSearching: Bool
    /// Grid instead of list, for image-heavy folders.
    let useGrid: Bool
    /// Resolves a row's git state. A closure rather than the provider itself so
    /// the list stays testable and unaware of how status is fetched.
    let gitStatus: (URL) -> GitFileStatus?
    let isCut: (URL) -> Bool
    /// Right-click actions. The list itself performs none of them.
    let menuActions: FileRowMenuActions
    /// Opening a search hit navigates to it — the list cannot do that itself
    /// because a hit may live several directories down.
    let onOpenHit: (SearchHit) -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    /// Captured once, NOT a computed property: a computed `Date()` would be
    /// evaluated per row, so a 5,000-entry directory would allocate 5,000
    /// dates. Refreshed when the listing changes, which is the only time
    /// "today vs. older" can shift meaningfully.
    @State private var now = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .onChange(of: tab.currentDirectory) { _, _ in now = Date() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = tab.loadError {
            AinkradErrorState(message: error, retryTitle: "Retry") { tab.reload() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let searchHits {
            if searchHits.isEmpty && !isSearching {
                AinkradEmptyState(icon: "magnifyingglass", title: "No Matches",
                                  message: "Nothing under this folder matches.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                searchResults(searchHits)
            }
        } else if tab.visibleEntries.isEmpty {
            AinkradEmptyState(icon: "folder", title: "Empty",
                              message: "This folder has nothing to show.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    if useGrid {
                        gridBody
                    } else {
                    LazyVStack(spacing: 1) {
                        ForEach(tab.visibleEntries) { entry in
                            FileRowView(
                                entry: entry,
                                isCursor: tab.cursorEntry == entry,
                                isSelected: tab.selection.contains(entry.url),
                                now: now,
                                iconSize: iconSize,
                                rowPadding: rowPadding,
                                showMetadata: showMetadata,
                                gitStatus: gitStatus(entry.url),
                                isIgnored: tab.ignoredURLs.contains(entry.url),
                                isCut: isCut(entry.url),
                                onTap: { tab.placeCursor(at: entry) },
                                onDoubleTap: { tab.activate(entry) }
                            )
                            .fileRowMenu(entry: entry, tab: tab, actions: menuActions)
                            .id(entry.url)
                        }
                    }
                    .padding(.horizontal, HoardColumnMetrics.rowStackInset)
                    .padding(.vertical, AinkradSpacing.xs)
                    }
                }
                // Keyed on the DIRECTORY, so arriving somewhere new builds a
                // fresh scroll view that necessarily starts at the top.
                //
                // A `ScrollView` keeps its content offset when its contents
                // change. Leaving a folder you had scrolled down in and
                // entering a shorter one therefore left the view parked past
                // the end of the new listing — a blank pane, with the status
                // bar cheerfully reporting "5 items" underneath it. It read as
                // a folder that had failed to load, and it "recovered" only by
                // visiting something long enough to reach the stale offset.
                //
                // Deliberately NOT `proxy.scrollTo` on navigation: that needs
                // the target row to be registered with the lazy stack at the
                // moment the change fires, and silently does nothing when it
                // is not. Identity has no such timing dependency.
                //
                // Keyed on the directory and not on the entries, so the
                // watcher's reload after a file changes keeps your scroll
                // position — being thrown to the top because something wrote
                // to the folder you are reading would be its own bug.
                .id(tab.currentDirectory)
                .onChange(of: tab.cursorIndex) { _, _ in
                    guard let entry = tab.cursorEntry else { return }
                    // `anchor: nil` scrolls the MINIMUM distance needed to
                    // bring the row into view. Passing `.center` re-centred
                    // the whole list on every arrow press — the list lurched
                    // under you instead of scrolling at the edges.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        proxy.scrollTo(entry.url, anchor: nil)
                    }
                }
            }
        }
    }

    /// Scoped-search results: same rows, plus WHERE each hit lives, which is
    /// the column that makes a recursive search readable.
    private func searchResults(_ hits: [SearchHit]) -> some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(hits) { hit in
                    HStack(spacing: 0) {
                        FileRowView(
                            entry: hit.entry,
                            isCursor: false,
                            isSelected: tab.selection.contains(hit.entry.url),
                            now: now,
                            iconSize: iconSize,
                            rowPadding: rowPadding,
                            showMetadata: false,
                            gitStatus: gitStatus(hit.entry.url),
                            isIgnored: false,
                            isCut: isCut(hit.entry.url),
                            onTap: { tab.selection = [hit.entry.url] },
                            onDoubleTap: { onOpenHit(hit) })
                            .fileRowMenu(entry: hit.entry, tab: tab, actions: menuActions)
                        Text(hit.relativeDirectory)
                            .font(AinkradFontResolver.font(.caption, typography: typo))
                            .foregroundStyle(theme.foreground.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(width: 180, alignment: .trailing)
                            .padding(.trailing, AinkradSpacing.sm)
                    }
                }
            }
            .padding(.horizontal, HoardColumnMetrics.rowStackInset)
            .padding(.vertical, AinkradSpacing.xs)
        }
    }

    /// Icon grid. Cell size follows the icon-size setting, so the one density
    /// control governs both presentations rather than each having its own.
    private var gridBody: some View {
        let cell = max(72, CGFloat(iconSize) * 5)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: AinkradSpacing.sm)],
                         spacing: AinkradSpacing.sm) {
            ForEach(tab.visibleEntries) { entry in
                FileGridCell(
                    entry: entry,
                    isCursor: tab.cursorEntry == entry,
                    isSelected: tab.selection.contains(entry.url),
                    iconSize: iconSize * 2.2,
                    onTap: { tab.placeCursor(at: entry) },
                    onDoubleTap: { tab.activate(entry) })
                    .fileRowMenu(entry: entry, tab: tab, actions: menuActions)
                    .id(entry.url)
            }
        }
        .padding(AinkradSpacing.md)
    }

    /// Click-to-sort column titles. No divider under the header — the design
    /// language forbids separator lines; separation reads via spacing.
    private var header: some View {
        HStack(spacing: AinkradSpacing.sm) {
            headerButton("Name", key: .name)
            Spacer(minLength: AinkradSpacing.md)
            if showMetadata {
                headerButton("Size", key: .size)
                    .frame(width: HoardColumnMetrics.sizeWidth, alignment: .trailing)
                headerButton("Modified", key: .modified)
                    .frame(width: HoardColumnMetrics.modifiedWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, HoardColumnMetrics.headerInset)
        .padding(.bottom, AinkradSpacing.xs)
        // The sortable header is meaningless over a grid.
        .opacity(useGrid ? 0 : 1)
        .frame(height: useGrid ? 0 : nil)
    }

    private func headerButton(_ title: String, key: FileSortKey) -> some View {
        Button {
            // Mirrors `nextSort(current:column:)` from the kit: a new column
            // starts ascending, the active column toggles direction.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                if tab.sortKey == key {
                    tab.sortAscending.toggle()
                } else {
                    tab.sortKey = key
                    tab.sortAscending = true
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title.uppercased())
                    .font(AinkradFontResolver.font(.caption, weight: .medium, typography: typo))
                    .tracking(0.9)
                Image(systemName: "chevron.up")
                    .font(.system(size: 7, weight: .bold))
                    // Kept in the layout at zero opacity when inactive, so
                    // sorting a column doesn't shift the header text sideways.
                    .opacity(tab.sortKey == key ? 1 : 0)
                    .rotationEffect(.degrees(tab.sortAscending ? 0 : 180))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                               value: tab.sortAscending)
            }
            .foregroundStyle(theme.foreground.opacity(tab.sortKey == key ? 0.75 : 0.4))
        }
        .buttonStyle(.plain)
    }
}
