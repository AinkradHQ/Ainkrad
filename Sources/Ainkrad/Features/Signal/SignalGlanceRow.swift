import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
import SwiftUI

/// One event in the bell dropdown, in the toast's vocabulary: the sending
/// app's launcher icon, the link's symbol beside the title, a one-line body
/// with a chevron when it is cut, and icon actions on hover (the event's own,
/// then mark read and dismiss). The full feed keeps `SignalFeedRow`, which has
/// room for labels.
struct SignalGlanceRow: View {
    let event: SignalEvent
    var repeatCount: Int = 1
    var isUnread: Bool = false
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkRead: (SignalEvent) -> Void = { _ in }
    var onDismiss: (SignalEvent) -> Void = { _ in }

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradSignalIdentity) private var identities
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var expanded = false
    @State private var overflowing = false

    private var accent: Color {
        SignalPresentation.status(for: event.severity).color(in: theme, statusColors: status)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.sm + 2) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                bodyLine
            }
        }
        .padding(.horizontal, AinkradSpacing.sm + 2)
        .padding(.vertical, AinkradSpacing.sm)
        .background(ChamferShape(cut: 6).fill(rowFill))
        // Severity as an edge, as on the toast; info has none.
        .overlay(alignment: .leading) {
            if event.severity != .info {
                Capsule().fill(accent).frame(width: 2).padding(.vertical, 7)
                    .shadow(color: accent.opacity(0.6), radius: 3)
            }
        }
        .contentShape(ChamferShape(cut: 6))
        .onTapGesture { onActivate(event) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: hovering)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: expanded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            SignalPresentation.accessibilityLabel(
                for: event, repeatCount: repeatCount, isUnread: isUnread, now: now)
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onActivate(event) }
        .accessibilityActions {
            ForEach(event.actions, id: \.id) { action in Button(action.label) { onAction(event, action) } }
            if isUnread { Button("Mark read") { onMarkRead(event) } }
            Button("Dismiss") { onDismiss(event) }
        }
    }

    /// Unread rows sit on a faint fill so they read as new without a badge on
    /// every row; hover brightens any row.
    private var rowFill: Color {
        if hovering { return theme.surfaceElevated.opacity(0.7) }
        return isUnread ? theme.surfaceElevated.opacity(0.32) : .clear
    }

    @ViewBuilder
    private var icon: some View {
        if let identity = identities.identity(for: event.source) {
            AinkradAppTile(symbol: identity.symbol, size: 28)
                .allowsHitTesting(false)
        } else {
            Image(systemName: SignalPresentation.iconSymbol(for: event.severity))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
        }
    }

    private var titleLine: some View {
        HStack(spacing: AinkradSpacing.xs + 1) {
            if let symbol = event.deepLink?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accentSecondary)
            }
            Text(event.title)
                .font(AinkradFont.display(12, weight: isUnread ? .semibold : .medium))
                .foregroundStyle(theme.foreground.opacity(isUnread ? 1 : 0.78))
                .lineLimit(1)
            if repeatCount > 1 {
                Text("×\(repeatCount)")
                    .font(AinkradFont.display(10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.accentSecondary)
            }
            Spacer(minLength: AinkradSpacing.xs)
            Text(SignalPresentation.relativeTime(event.timestamp, now: now))
                .font(AinkradFont.display(10))
                .foregroundStyle(theme.foreground.opacity(0.4))
            if overflowing || expanded {
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.foreground.opacity(hovering ? 0.7 : 0.4))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Show less" : "Show the whole message")
            }
            Circle()
                .fill(theme.accentSecondary)
                .frame(width: 5, height: 5)
                .opacity(isUnread ? 1 : 0)
        }
    }

    /// The body, with the actions beside it shown while hovered. Their space
    /// is reserved, so the text never reflows and nothing moves on hover.
    private var bodyLine: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.xs + 2) {
            bodyText
                .lineLimit(expanded ? 30 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // The same text unclamped and invisible: taller than the
                    // clamped line means it was cut, so the chevron appears.
                    GeometryReader { clamped in
                        bodyText
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: clamped.size.width, alignment: .leading)
                            .hidden()
                            .background(
                                GeometryReader { full in
                                    Color.clear.onAppear { overflowing = full.size.height > clamped.size.height + 1 }
                                        .onChange(of: clamped.size.width) {
                                            if !expanded { overflowing = full.size.height > clamped.size.height + 1 }
                                        }
                                })
                    }
                    .allowsHitTesting(false)
                }
            // Always laid out, only faded: appearing on hover made every row
            // grow and its text re-truncate under the pointer.
            actions
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .accessibilityHidden(true)
        }
    }

    private var bodyText: Text {
        Text(event.body.flatMap { $0.isEmpty ? nil : $0 } ?? " ")
            .font(AinkradFont.display(11))
            .foregroundStyle(theme.foreground.opacity(0.62))
    }

    private var actions: some View {
        HStack(spacing: AinkradSpacing.xs) {
            ForEach(event.actions.prefix(2), id: \.id) { action in
                iconButton(
                    action.symbol ?? "arrow.up.forward.circle", help: action.label,
                    tint: action.isDestructive ? status.danger : theme.accentPrimary
                ) {
                    onAction(event, action)
                }
            }
            if isUnread {
                iconButton("envelope.open", help: "Mark read", tint: theme.foreground.opacity(0.75)) {
                    onMarkRead(event)
                }
            }
            iconButton("trash", help: "Dismiss", tint: theme.foreground.opacity(0.75)) { onDismiss(event) }
        }
    }

    private func iconButton(_ symbol: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 18)
                .background(ChamferShape(cut: 4).fill(tint.opacity(0.12)))
                .contentShape(ChamferShape(cut: 4))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
