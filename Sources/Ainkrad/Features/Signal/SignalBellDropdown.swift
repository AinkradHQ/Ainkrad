import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
import SwiftUI

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
    @State private var listHeight: CGFloat = 0

    enum ReadFilter: String, CaseIterable, Hashable {
        case all = "All"
        case unread = "Unread"
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
                    // Sized to the list, up to the cap, then it scrolls. A
                    // flexible frame took the whole cap and centred one row in it.
                    ScrollView {
                        list.background(
                            GeometryReader { geo in
                                Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                            })
                    }
                    .scrollIndicators(.never)
                    .scrollDisabled(listHeight <= Self.maxListHeight)
                    .frame(height: min(listHeight, Self.maxListHeight))
                    .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
                }
                footer
            }
            .frame(width: 380)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups, id: \.source) { group in
                // Filtered to one app, its events are the whole list: grouping
                // them behind a stack would hide exactly what was asked for.
                let isFlat = appFilter != nil
                let isOpen = isFlat || expandedGroups.contains(group.source)
                if isOpen || group.events.count == 1 {
                    ForEach(isFlat ? group.events : Array(group.events.prefix(Self.maxPerGroup))) { event in
                        glanceRow(event)
                    }
                    if !isFlat && group.events.count > 1 {
                        HStack {
                            Spacer()
                            countChip("Show less", systemName: "chevron.up") { toggle(group.source) }
                        }
                        .padding(.trailing, 4)
                    }
                } else {
                    stack(group)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: expandedGroups)
    }

    private func glanceRow(_ event: SignalEvent) -> some View {
        SignalGlanceRow(
            event: event,
            repeatCount: repeatCounts[event.id] ?? 1,
            isUnread: !readIDs.contains(event.id),
            now: now,
            onActivate: onActivate,
            onAction: onAction,
            onMarkRead: onMarkRead,
            onDismiss: onDismissEvent)
    }

    /// A collapsed group: the newest event on top of a stack whose edges peek
    /// out below it (a layer per hidden event, up to two), with the count on
    /// the stack's edge. Tapping the edges or the count opens the group.
    private func stack(_ group: (source: SignalSource, events: [SignalEvent])) -> some View {
        let hidden = group.events.count - 1
        let layers = min(hidden, 2)
        return ZStack(alignment: .top) {
            ForEach((1...max(layers, 1)).reversed(), id: \.self) { depth in
                ChamferShape(cut: 6)
                    .fill(theme.surfaceElevated.opacity(depth == 1 ? 0.55 : 0.32))
                    .overlay(ChamferShape(cut: 6).strokeBorder(theme.accentSecondary.opacity(0.14), lineWidth: 1))
                    .padding(.horizontal, CGFloat(depth) * 7)
                    .offset(y: CGFloat(depth) * 5)
                    .opacity(depth <= layers ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(group.source) }
            }
            glanceRow(group.events[0])
                .background(ChamferShape(cut: 6).fill(theme.surfaceElevated.opacity(0.9)))
        }
        .padding(.bottom, CGFloat(layers) * 5 + 4)
        .overlay(alignment: .bottomTrailing) {
            countChip("+\(hidden)", systemName: "chevron.down") { toggle(group.source) }
                .padding(.trailing, 10)
                .offset(y: 2)
        }
    }

    /// The group count, and "Show less", as one small chamfered chip in the
    /// accent, rather than a line of link text under the row.
    private func countChip(_ text: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(text).font(AinkradFont.display(9.5, weight: .semibold)).monospacedDigit()
                Image(systemName: systemName).font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(theme.accentSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(ChamferShape(cut: 3).fill(theme.surface))
            .background(ChamferShape(cut: 3).fill(theme.accentSecondary.opacity(0.16)))
            .overlay(ChamferShape(cut: 3).strokeBorder(theme.accentSecondary.opacity(0.4), lineWidth: 1))
            .contentShape(ChamferShape(cut: 3))
        }
        .buttonStyle(.plain)
        .help(text == "Show less" ? "Show less" : "Show \(text.dropFirst()) more")
    }

    private func toggle(_ source: SignalSource) {
        if expandedGroups.contains(source) { expandedGroups.remove(source) } else { expandedGroups.insert(source) }
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
                AinkradMenuButton(
                    items: SignalSnooze.allCases.map { snooze in
                        AinkradMenuItem(title: snooze.label, systemName: "bell.slash") { onSnooze(snooze) }
                    }
                ) {
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

    private func headerButton(
        _ symbol: String, help: String, tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
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
                LinearGradient(
                    colors: [.clear, theme.surfaceElevated.opacity(hoveringFooter ? 0.85 : 0.55)],
                    startPoint: .top, endPoint: .bottom)
            }
            .background(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, theme.accentPrimary.opacity(0.22)],
                    startPoint: .top, endPoint: .bottom
                )
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

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
