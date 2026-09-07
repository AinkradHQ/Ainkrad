import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The feed rendered as collapsible per-app groups.
///
/// The point is that a burst is one line until you open it: nineteen identical
/// warnings from one app should cost the reader one row, not nineteen.
struct SignalFeedGroupedList: View {
    let groups: [SignalSourceGroup]
    @Binding var collapsed: Set<String>
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var menuItems: (SignalEvent) -> [AinkradMenuItem] = { _ in [] }
    var pinnedIDs: Set<UUID> = []
    var expandedIDs: Binding<Set<UUID>> = .constant([])

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    /// Eight, because a 25ms stagger across nineteen rows stops reading as
    /// motion and starts reading as lag.
    private static let staggerCap = 8

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AinkradSpacing.xs / 2) {
                ForEach(groups) { group in
                    header(group)
                    if !collapsed.contains(group.id) {
                        // Enumerated so each child can carry its own delay:
                        // the group opens as separated layers settling rather
                        // than one block appearing, which is the host's motion
                        // rule. Capped, because a stagger across nineteen rows
                        // stops reading as motion and starts reading as lag.
                        ForEach(Array(group.events.enumerated().prefix(Self.staggerCap)),
                                id: \.element.id) { index, event in
                            row(group: group, event: event)
                                .transition(reduceMotion ? .opacity : .opacity.animation(
                                    .easeOut(duration: AinkradMotion.durationFast)
                                        .delay(Double(index) * 0.025)))
                        }
                        if group.events.count > Self.staggerCap {
                            ForEach(group.events.dropFirst(Self.staggerCap)) { event in
                                row(group: group, event: event)
                            }
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: AinkradMotion.durationBase),
                       value: collapsed)
            .padding(.vertical, AinkradSpacing.xs + 2)
            .padding(.horizontal, AinkradSpacing.xs + 2)
        }
    }

    private func row(group: SignalSourceGroup, event: SignalEvent) -> some View {
        SignalFeedRow(
            event: event,
            repeatCount: repeatCounts[event.id] ?? 1,
            isUnread: !readIDs.contains(event.id),
            now: now,
            onActivate: onActivate,
            onAction: onAction,
            menuItems: menuItems,
            isPinned: pinnedIDs.contains(event.id),
            isExpanded: expandedIDs.wrappedValue.contains(event.id),
            onToggleExpanded: {
                if expandedIDs.wrappedValue.contains(event.id) {
                    expandedIDs.wrappedValue.remove(event.id)
                } else {
                    expandedIDs.wrappedValue.insert(event.id)
                }
            })
    }

    private func header(_ group: SignalSourceGroup) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return Button {
            if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
        } label: {
            HStack(spacing: AinkradSpacing.xs + 2) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.foreground.opacity(0.45))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Circle()
                    .fill(group.worstUnread.map {
                        SignalPresentation.status(for: $0).color(in: theme, statusColors: status)
                    } ?? .clear)
                    .frame(width: 5, height: 5)
                Text(group.name)
                    .font(AinkradFont.display(11.5, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                // A collapsed group has to say something specific, or the user
                // must expand every one to find the thing they came for.
                if isCollapsed, let preview = group.preview {
                    Text(preview)
                        .font(AinkradFont.display(10.5))
                        .foregroundStyle(theme.foreground.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: AinkradSpacing.xs)
                // The total only when it says something the badge does not.
                // With everything unread the two are the same number, and
                // printing it twice reads as a rendering mistake.
                if group.unread != group.events.count {
                    Text("\(group.events.count)")
                        .font(AinkradFont.mono(9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.foreground.opacity(0.45))
                }
                if group.unread > 0 {
                    AinkradBadge(text: "\(group.unread) new", tint: theme.accentSecondary)
                }
            }
            .padding(.horizontal, AinkradSpacing.md)
            .padding(.vertical, AinkradSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A tint band, not a rule: the design language forbids separators,
            // and a group header still has to read as a boundary.
            .background(theme.surface.opacity(0.92))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
