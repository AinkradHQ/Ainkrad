import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The in-window feed: a source rail, severity filters, search, and the list.
///
/// Reads its rows through closures rather than owning a store, so the same view
/// renders live host state and a seeded snapshot without a second code path.
struct SignalFeedIsland: View {
    let events: [SignalEvent]
    var unread: Int = 0
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var isDegraded: Bool = false
    var now: Date = Date()
    /// Persisted, so the filter the user built survives closing the overlay.
    @Binding var viewState: SignalViewState
    var searchText: Binding<String>
    /// Nil when not searching; a count when searching, even if it is zero.
    var searchResultCount: Int?
    var displayName: (SignalSource) -> String = { SignalPresentation.sourceLabel($0) }
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkAllRead: () -> Void = {}
    var onConfigureSource: (SignalSource) -> Void = { _ in }
    var menuItems: (SignalEvent) -> [AinkradMenuItem] = { _ in [] }
    var pinnedIDs: Set<UUID> = []
    var expandedIDs: Binding<Set<UUID>> = .constant([])
    /// Quiet hours or a snooze is in force.
    var isMuted: Bool = false
    /// The same two durations the bell dropdown and Settings offer. This
    /// surface used to offer none, so a user who opened the full feed to deal
    /// with a noisy session had to leave it again to quieten anything.
    var onSnooze: (SignalSnooze) -> Void = { _ in }
    var onResume: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    /// Whether the chip row is showing. Not persisted: a row with filters set
    /// is shown regardless, so the only thing this remembers is whether an
    /// empty chip row is currently open, which is not a view the user built.
    @State private var showsFilters = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    /// Severity, source and unread are applied here rather than by re-querying:
    /// the caller may have handed us search results, and re-filtering in the
    /// store would discard them.
    private var filtered: [SignalEvent] {
        events.filter { event in
            (viewState.severities.isEmpty || viewState.severities.contains(event.severity))
                && (viewState.selectedSource == nil || event.source == viewState.selectedSource)
                && (!viewState.unreadOnly || !readIDs.contains(event.id))
        }
    }

    private var railItems: [SignalSourceRailItem] {
        SignalSourceRailItem.build(events: events, readIDs: readIDs, name: displayName)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SignalSourceRail(items: railItems,
                             selection: $viewState.selectedSource,
                             onConfigure: onConfigureSource)
            VStack(alignment: .leading, spacing: 0) {
                header
                if showsFilters || viewState.chipFilterCount > 0 {
                    filterBar
                        // Wipes down from the header it belongs to rather than
                        // fading in place, so the rows below are seen to make
                        // room instead of being covered.
                        .transition(reduceMotion
                                    ? .opacity
                                    : .move(edge: .top).combined(with: .opacity))
                }
                if isDegraded { degradedNotice }
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty && !events.isEmpty {
            noMatches
        } else if viewState.effectiveGrouping == .bySource {
            SignalFeedGroupedList(
                groups: SignalPresentation.sourceGroups(filtered, readIDs: readIDs,
                                                        name: displayName),
                collapsed: $viewState.collapsedSources,
                repeatCounts: repeatCounts, readIDs: readIDs, now: now,
                onActivate: onActivate, onAction: onAction, menuItems: menuItems,
                pinnedIDs: pinnedIDs, expandedIDs: expandedIDs)
        } else {
            SignalFeedList(events: filtered, repeatCounts: repeatCounts, readIDs: readIDs,
                           now: now, calendar: .current, onActivate: onActivate,
                           onAction: onAction, menuItems: menuItems,
                           pinnedIDs: pinnedIDs, expandedIDs: expandedIDs)
        }
    }

    private var header: some View {
        HStack(spacing: AinkradSpacing.sm + 2) {
            Text("Notifications")
                .font(AinkradFont.display(15, weight: .semibold))
                .foregroundStyle(theme.foreground)
                // Never wrapped. The header grew a Filters control, and at the
                // overlay's minimum width SwiftUI paid for it by breaking the
                // title across two lines — which reads as a layout fault, not
                // as a tight fit.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if unread > 0 {
                AinkradBadge(text: "\(unread) new", tint: theme.accentSecondary)
                    .fixedSize()
            }
            Spacer(minLength: AinkradSpacing.sm)
            filtersButton
                .fixedSize()
            // The one flexible element in the row. Everything else here is a
            // label or a glyph whose width is its content; the search field is
            // the only thing that can give, so it is the only thing allowed to.
            AinkradSearchField(text: searchText, placeholder: "Search")
                .frame(minWidth: 120, maxWidth: 190)
            quietControl
            if unread > 0 {
                Button(action: onMarkAllRead) {
                    // Names what it will actually do. Under a filter, "Mark all
                    // read" reads as everything and quietly means twelve — so
                    // the user clears rows they cannot see.
                    Text(viewState.isShowingEverything
                         ? "Mark all read"
                         : "Mark \(filtered.filter { !readIDs.contains($0.id) }.count) read")
                        .font(AinkradFont.display(10.5, weight: .medium))
                        .foregroundStyle(theme.accentPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.top, AinkradSpacing.lg - 2)
        .padding(.bottom, AinkradSpacing.sm + 2)
    }

    /// One affordance instead of five chips sitting above a list that is
    /// usually short. Chips appear on demand — and stay visible whenever
    /// anything is actually filtering, because a hidden active filter is how a
    /// user concludes the feed has lost their events.
    private var filtersButton: some View {
        let count = viewState.chipFilterCount
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: AinkradMotion.durationFast)) {
                showsFilters.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 9.5, weight: .medium))
                Text(count > 0 ? "Filters · \(count)" : "Filters")
                    .font(AinkradFont.display(10.5, weight: .medium))
            }
            .foregroundStyle(count > 0 ? theme.accentSecondary
                                       : theme.foreground.opacity(0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(count > 0 ? "\(count) filters active" : "Filter this feed")
        .accessibilityLabel(count > 0 ? "Filters, \(count) active" : "Filters")
    }

    /// The same shape the bell dropdown uses: a menu offering both durations,
    /// collapsing to a single Resume once something is in force.
    @ViewBuilder
    private var quietControl: some View {
        let glyph = Image(systemName: isMuted ? "bell.slash.fill" : "bell.slash")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isMuted ? theme.accentSecondary
                                     : theme.foreground.opacity(0.45))
        if isMuted {
            Button(action: onResume) { glyph }
                .buttonStyle(.plain)
                .help("Resume now")
                .accessibilityLabel("Resume now")
        } else {
            // The kit's own menu, not SwiftUI's `Menu`: that renders a stock
            // AppKit menu -- grey slab, system corner radius, system highlight
            // -- which landed in the middle of the HUD looking like it belonged
            // to another application.
            AinkradMenuButton(items: SignalSnooze.allCases.map { snooze in
                AinkradMenuItem(title: snooze.label, systemName: "bell.slash") {
                    onSnooze(snooze)
                }
            }) {
                glyph
            }
            .help("Go quiet")
            .accessibilityLabel("Go quiet")
        }
    }

    private var filterBar: some View {
        HStack(spacing: AinkradSpacing.xs + 2) {
            ForEach(SignalSeverity.allCases, id: \.self) { severity in
                AinkradSwatchChip(
                    label: severity.rawValue.capitalized,
                    swatch: SignalPresentation.status(for: severity)
                        .color(in: theme, statusColors: status),
                    isOn: viewState.severities.contains(severity)) {
                    if viewState.severities.contains(severity) {
                        viewState.severities.remove(severity)
                    } else {
                        viewState.severities.insert(severity)
                    }
                }
            }
            AinkradSwatchChip(label: "Unread", swatch: theme.accentSecondary,
                              isOn: viewState.unreadOnly) {
                viewState.unreadOnly.toggle()
            }
            Spacer()
            if let count = searchResultCount {
                // A search that silently replaces the list is the reason the
                // empty state used to be a dead end: the user could not tell
                // whether a filter or a query had emptied it.
                Text(count == 1 ? "1 result" : "\(count) results")
                    .font(AinkradFont.mono(9.5))
                    .foregroundStyle(theme.foreground.opacity(0.5))
            }
            // Only where it can say anything. With a source selected every
            // event is from that source, so this and the rail were two controls
            // answering one question — and their combination was a single
            // group whose header named what the rail already named.
            if viewState.canGroupBySource {
                AinkradSegmentedPicker(
                    items: [SignalViewState.Grouping.byTime, .bySource],
                    selection: $viewState.grouping,
                    label: { $0 == .byTime ? "Time" : "App" })
            }
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.bottom, AinkradSpacing.sm)
    }

    /// The feed still works with no store - it just cannot remember. Saying so
    /// is better than a mysteriously short history.
    private var degradedNotice: some View {
        HStack(spacing: AinkradSpacing.sm - 1) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10.5))
                .foregroundStyle(status.warning)
            Text("History unavailable — events are kept in memory for this session only.")
                .font(AinkradFont.display(10.5))
                .foregroundStyle(theme.foreground.opacity(0.62))
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.vertical, AinkradSpacing.sm - 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceElevated.opacity(0.6))
    }

    private var noMatches: some View {
        VStack(spacing: AinkradSpacing.sm) {
            Text("No matching events")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.55))
            // Clears the SEARCH as well as the filters. The old button cleared
            // only the chips, so a user who had searched stayed stuck in an
            // empty feed with a button that appeared not to work.
            AinkradButton(title: "Clear all", style: .ghost) {
                viewState.severities.removeAll()
                viewState.selectedSource = nil
                viewState.unreadOnly = false
                searchText.wrappedValue = ""
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AinkradSpacing.xl + AinkradSpacing.lg)
    }
}
