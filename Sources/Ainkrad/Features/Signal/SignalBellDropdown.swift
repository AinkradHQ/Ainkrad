import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The bell's dropdown: what just happened, grouped by the app that said it,
/// in the shared HUD panel finish (`AinkradPanel`).
///
/// Rows match the toast: the app's launcher icon, the link's symbol (a chat's
/// service) beside the title, a one-line body that expands, and icon actions
/// on hover. Each app shows its newest event with "+N more" behind it, so a
/// burst from one app cannot push everything else out, and the list scrolls
/// past a screenful instead of stopping at five. "View all" still hands off to
/// the full feed, where search and history live.
struct SignalBellDropdown: View {
    let events: [SignalEvent]
    let unread: Int
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkRead: (SignalEvent) -> Void = { _ in }
    var onDismissEvent: (SignalEvent) -> Void = { _ in }
    var onMarkAllRead: () -> Void = {}
    var onViewAll: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Quiet hours or a snooze is in force.
    var isMuted: Bool = false
    /// Go quiet, or come back. Offered HERE because this is where the user is
    /// when they notice the noise.
    var onSnooze: (SignalSnooze) -> Void = { _ in }
    var onResume: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradSignalIdentity) private var identities
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hoveringFooter = false
    @State private var readFilter: ReadFilter = .all
    @State private var appFilter: SignalSource?
    @State private var expandedGroups: Set<SignalSource> = []

    enum ReadFilter: String, CaseIterable, Hashable {
        case all = "All", unread = "Unread"
    }

    /// Tallest the list grows before it scrolls.
    private static let maxListHeight: CGFloat = 440
    /// Most events one expanded group shows; the feed has the rest.
    private static let maxPerGroup = 8

    private var filtered: [SignalEvent] {
        events.filter { event in
            (readFilter == .all || !readIDs.contains(event.id))
                && (appFilter == nil || event.source == appFilter)
        }
    }

    /// Sources in order of their newest event, each with its events newest first.
    private var groups: [(source: SignalSource, events: [SignalEvent])] {
        var order: [SignalSource] = []
        var bySource: [SignalSource: [SignalEvent]] = [:]
        for event in filtered {
            if bySource[event.source] == nil { order.append(event.source) }
            bySource[event.source, default: []].append(event)
        }
        return order.map { ($0, bySource[$0] ?? []) }
    }

    /// Every app that has something in the feed, for the filter tiles.
    private var sources: [SignalSource] {
        var seen: [SignalSource] = []
        for event in events where !seen.contains(event.source) { seen.append(event.source) }
        return seen
    }

    var body: some View {
        AinkradPanel(showsBrackets: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !events.isEmpty { filters }
                if groups.isEmpty {
                    empty
                } else {
                    ViewThatFits(in: .vertical) {
                        list
                        ScrollView { list }.scrollIndicators(.never)
                    }
                    .frame(maxHeight: Self.maxListHeight)
                }
                footer
            }
            .frame(width: 380)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(groups, id: \.source) { group in
                // Filtered to one app, its events are the whole list: grouping
                // them behind "+N more" would hide exactly what was asked for.
                let isFlat = appFilter != nil
                let isOpen = isFlat || expandedGroups.contains(group.source)
                let visible = isFlat ? group.events
                    : isOpen ? Array(group.events.prefix(Self.maxPerGroup)) : [group.events[0]]
                ForEach(visible) { event in
                    SignalGlanceRow(event: event,
                                    repeatCount: repeatCounts[event.id] ?? 1,
                                    isUnread: !readIDs.contains(event.id),
                                    now: now,
                                    onActivate: onActivate,
                                    onAction: onAction,
                                    onMarkRead: onMarkRead,
                                    onDismiss: onDismissEvent)
                }
                if !isFlat && group.events.count > 1 {
                    moreToggle(group.source, remaining: group.events.count - 1, isOpen: isOpen)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: expandedGroups)
    }

    private func moreToggle(_ source: SignalSource, remaining: Int, isOpen: Bool) -> some View {
        let name = identities.identity(for: source)?.name ?? SignalPresentation.sourceLabel(source)
        return Button {
            if isOpen { expandedGroups.remove(source) } else { expandedGroups.insert(source) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                Text(isOpen ? "Show less from \(name)" : "+\(remaining) more from \(name)")
                    .font(AinkradFont.display(10, weight: .medium))
            }
            .foregroundStyle(theme.accentPrimary.opacity(0.85))
            .padding(.leading, 48)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: AinkradSpacing.sm) {
            Text("Notifications")
                .font(AinkradFont.display(11.5, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .textCase(.uppercase)
                .tracking(0.6)
            if unread > 0 {
                AinkradBadge(text: "\(unread)", tint: theme.accentSecondary)
            }
            Spacer()
            if unread > 0 {
                headerButton("checkmark.circle", help: "Mark all read", action: onMarkAllRead)
            }
            if isMuted {
                headerButton("bell.slash.fill", help: "Resume now", tint: theme.accentSecondary, action: onResume)
            } else {
                // The kit's own menu, not SwiftUI's `Menu`, which renders a
                // stock AppKit menu in the middle of the HUD.
                AinkradMenuButton(items: SignalSnooze.allCases.map { snooze in
                    AinkradMenuItem(title: snooze.label, systemName: "bell.slash") { onSnooze(snooze) }
                }) {
                    headerGlyph("bell.slash")
                }
                .help("Go quiet")
                .accessibilityLabel("Go quiet")
            }
            headerButton("gearshape", help: "Notification settings", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func headerGlyph(_ symbol: String, tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint ?? theme.foreground.opacity(0.5))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }

    private func headerButton(_ symbol: String, help: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { headerGlyph(symbol, tint: tint) }
            .buttonStyle(.plain)
            .help(help)
            // Icon-only, so `help` is not enough: a listener never gets a tooltip.
            .accessibilityLabel(help)
    }

    /// All / Unread, then one tile per app: the launcher icon, selected when
    /// it is the filter. Tapping the selected app clears it.
    private var filters: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradSegmentedPicker(items: ReadFilter.allCases, selection: $readFilter) { $0.rawValue }
                .frame(width: 128)
            Spacer(minLength: AinkradSpacing.xs)
            if sources.count > 1 {
                ForEach(sources, id: \.self) { source in
                    let identity = identities.identity(for: source)
                    Button {
                        appFilter = appFilter == source ? nil : source
                    } label: {
                        AinkradAppTile(symbol: identity?.symbol ?? "app", size: 22, isSelected: appFilter == source)
                    }
                    .buttonStyle(.plain)
                    .help(identity?.name ?? SignalPresentation.sourceLabel(source))
                    .accessibilityLabel("Only \(identity?.name ?? SignalPresentation.sourceLabel(source))")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// The hand-off. Chevron rather than an ellipsis: it goes somewhere.
    private var footer: some View {
        Button(action: onViewAll) {
            HStack(spacing: 5) {
                Text(events.count > 1 ? "View all \(events.count) notifications" : "View all notifications")
                    .font(AinkradFont.display(10.5, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .offset(x: hoveringFooter && !reduceMotion ? 2 : 0)
            }
            .foregroundStyle(theme.accentPrimary.opacity(hoveringFooter ? 1 : 0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            // A gradient that starts at nothing: no edge to read as a rule.
            .background {
                LinearGradient(colors: [.clear, theme.surfaceElevated.opacity(hoveringFooter ? 0.85 : 0.55)],
                               startPoint: .top, endPoint: .bottom)
            }
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, theme.accentPrimary.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .opacity(hoveringFooter ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: hoveringFooter)
        .onHover { hoveringFooter = $0 }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: readFilter == .unread || appFilter != nil ? "checkmark.circle" : "bell.slash")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(theme.foreground.opacity(0.3))
            Text(readFilter == .unread || appFilter != nil ? "All caught up" : "Nothing yet")
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
