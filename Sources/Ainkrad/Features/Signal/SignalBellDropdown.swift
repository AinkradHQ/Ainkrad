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
    @Environment(\.ainkradSkin) private var skin
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
            .frame(width: skin.size.s380)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: skin.spacing.xs) {
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
                        .padding(.trailing, skin.spacing.xs)
                    }
                } else {
                    stack(group)
                }
            }
        }
        .padding(.horizontal, skin.size.s6)
        .padding(.bottom, skin.size.s6)
        .animation(
            reduceMotion ? nil : skin.motion.springs["sp32_84"].map { skin.animation($0) }, value: expandedGroups)
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
                ChamferShape(cut: skin.cut.c6)
                    .fill(theme.surfaceElevated.opacity(depth == 1 ? skin.opacity.o55 : skin.opacity.o32))
                    .overlay(
                        ChamferShape(cut: skin.cut.c6)
                            .strokeBorder(theme.accentSecondary.opacity(skin.opacity.o14), lineWidth: 1)
                    )
                    .padding(.horizontal, CGFloat(depth) * skin.size.s7)
                    .offset(y: CGFloat(depth) * skin.size.s5)
                    .opacity(depth <= layers ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(group.source) }
            }
            glanceRow(group.events[0])
                .background(ChamferShape(cut: skin.cut.c6).fill(theme.surfaceElevated.opacity(skin.opacity.o90)))
        }
        .padding(.bottom, CGFloat(layers) * skin.size.s5 + skin.spacing.xs)
        .overlay(alignment: .bottomTrailing) {
            countChip("+\(hidden)", systemName: "chevron.down") { toggle(group.source) }
                .padding(.trailing, skin.size.s10)
                .offset(y: skin.size.s2)
        }
    }

    /// The group count, and "Show less", as one small chamfered chip in the
    /// accent, rather than a line of link text under the row.
    ///
    /// Local, not `AinkradChip`: the kit chip has no tap action, only a
    /// remove button (kit gap "action chip").
    private func countChip(_ text: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {  // design-lint: allow raw-control kit gap, action chip
            HStack(spacing: skin.size.s3) {
                Text(text).font(AinkradFont.display(9.5, weight: .semibold)).monospacedDigit()
                Image(systemName: systemName)
                    .font(skin.font(AinkradFontToken(sizeKey: "t7", weight: "bold", scaled: false)))
            }
            .foregroundStyle(theme.accentSecondary)
            .padding(.horizontal, skin.size.s7)
            .padding(.vertical, skin.size.s2_5)
            .background(ChamferShape(cut: skin.cut.c3).fill(theme.surface))
            .background(ChamferShape(cut: skin.cut.c3).fill(theme.accentSecondary.opacity(skin.opacity.o16)))
            .overlay(
                ChamferShape(cut: skin.cut.c3)
                    .strokeBorder(theme.accentSecondary.opacity(skin.opacity.o40), lineWidth: 1)
            )
            .contentShape(ChamferShape(cut: skin.cut.c3))
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
                headerButton("bell.slash.fill", help: "Resume now", action: onResume)
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
        .padding(.horizontal, skin.size.s14)
        .padding(.top, skin.spacing.md)
        .padding(.bottom, skin.spacing.sm)
    }

    /// The snooze menu's label: `AinkradMenuButton` takes a custom label.
    private func headerGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(skin.font(AinkradFontToken(sizeKey: "t11", weight: "medium", scaled: false)))
            .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
            .frame(width: skin.size.s20, height: skin.size.s20)
            .contentShape(Rectangle())
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        AinkradIconButton(systemName: symbol, size: skin.size.s20, tooltip: help, action: action)
            // Icon-only, so a tooltip is not enough: a listener never gets one.
            .accessibilityLabel(help)
    }

    /// All / Unread, then one tile per app: the launcher icon, selected when
    /// it is the filter. Tapping the selected app clears it.
    private var filters: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradSegmentedPicker(items: ReadFilter.allCases, selection: $readFilter) { $0.rawValue }
                .frame(width: skin.size.s128)
            Spacer(minLength: AinkradSpacing.xs)
            if sources.count > 1 {
                ForEach(sources, id: \.self) { source in
                    let identity = identities.identity(for: source)
                    // The label is the kit's app tile, which has no action of its own.
                    Button {  // design-lint: allow raw-control kit gap, content label
                        appFilter = appFilter == source ? nil : source
                    } label: {
                        AinkradAppTile(
                            symbol: identity?.symbol ?? "app", size: skin.size.s22, isSelected: appFilter == source)
                    }
                    .buttonStyle(.plain)
                    .help(identity?.name ?? SignalPresentation.sourceLabel(source))
                    .accessibilityLabel("Only \(identity?.name ?? SignalPresentation.sourceLabel(source))")
                }
            }
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.spacing.sm)
    }

    /// The hand-off. Chevron rather than an ellipsis: it goes somewhere.
    ///
    /// Local, not `AinkradButton`: the kit button hugs its label, and this is
    /// a full-width strip whose hover glow rises from the panel's bottom edge
    /// (kit gap "full-width footer action").
    private var footer: some View {
        Button(action: onViewAll) {  // design-lint: allow raw-control kit gap, full-width footer action
            HStack(spacing: skin.size.s5) {
                Text(events.count > 1 ? "View all \(events.count) notifications" : "View all notifications")
                    .font(AinkradFont.display(10.5, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(skin.font(AinkradFontToken(sizeKey: "t8", weight: "bold", scaled: false)))
                    .offset(x: hoveringFooter && !reduceMotion ? skin.size.s2 : 0)
            }
            .foregroundStyle(theme.accentPrimary.opacity(hoveringFooter ? 1 : skin.opacity.o82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, skin.size.s11)
            // A gradient that starts at nothing: no edge to read as a rule.
            .background {
                LinearGradient(
                    colors: [
                        .clear, theme.surfaceElevated.opacity(hoveringFooter ? skin.opacity.o85 : skin.opacity.o55),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .background(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, theme.accentPrimary.opacity(skin.opacity.o22)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: skin.size.s14)
                .opacity(hoveringFooter ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: hoveringFooter)
        .onHover { hoveringFooter = $0 }
    }

    private var empty: some View {
        VStack(spacing: skin.spacing.xs) {
            Image(systemName: readFilter == .unread || appFilter != nil ? "checkmark.circle" : "bell.slash")
                .font(skin.font(AinkradFontToken(sizeKey: "t15", weight: "light", scaled: false)))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o30))
            Text(readFilter == .unread || appFilter != nil ? "All caught up" : "Nothing yet")
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s22)
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
