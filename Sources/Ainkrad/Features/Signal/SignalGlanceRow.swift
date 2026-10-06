import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
import SwiftUI

/// One event in the bell dropdown, in the toast's vocabulary: the sending
/// app's launcher icon, the link's symbol beside the title, a one-line body
/// with a chevron when it is cut, and icon actions on hover (the event's own,
/// then mark read and dismiss). The full feed keeps `SignalFeedRow`, which has
/// room for labels.
///
/// Local, not `SignalFeedRow`: the kit row has no dense mode — no app-tile
/// icon, no hover icon actions with reserved space, no in-place expand
/// chevron driven by measured overflow (kit gap "glance row").
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
    @Environment(\.ainkradSkin) private var skin
    @State private var hovering = false
    @State private var expanded = false
    @State private var overflowing = false

    private var accent: Color {
        SignalPresentation.status(for: event.severity).color(in: theme, statusColors: status)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.sm + 2) {
            icon
            VStack(alignment: .leading, spacing: skin.size.s2) {
                titleLine
                bodyLine
            }
        }
        .padding(.horizontal, AinkradSpacing.sm + 2)
        .padding(.vertical, AinkradSpacing.sm)
        .background(ChamferShape(cut: skin.cut.c6).fill(rowFill))
        // Severity as an edge, as on the toast; info has none.
        .overlay(alignment: .leading) {
            if event.severity != .info {
                Capsule().fill(accent).frame(width: skin.size.s2).padding(.vertical, skin.size.s7)
                    .shadow(color: accent.opacity(skin.opacity.o60), radius: skin.size.s3)
            }
        }
        .contentShape(ChamferShape(cut: skin.cut.c6))
        .onTapGesture { onActivate(event) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: hovering)
        .animation(reduceMotion ? nil : skin.motion.springs["sp30_86"].map { skin.animation($0) }, value: expanded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            SignalPresentation.accessibilityLabel(
                for: event, repeatCount: repeatCount, isUnread: isUnread, now: now)
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onActivate(event) }
        .accessibilityActions {
            // Accessibility actions, never drawn: SwiftUI reads them only from
            // a plain `Button`.
            ForEach(event.actions, id: \.id) { action in
                Button(action.label) { onAction(event, action) }  // design-lint: allow raw-control a11y action
            }
            if isUnread { Button("Mark read") { onMarkRead(event) } }  // design-lint: allow raw-control a11y action
            Button("Dismiss") { onDismiss(event) }  // design-lint: allow raw-control a11y action
        }
    }

    /// Unread rows sit on a faint fill so they read as new without a badge on
    /// every row; hover brightens any row.
    private var rowFill: Color {
        if hovering { return theme.surfaceElevated.opacity(skin.opacity.o70) }
        return isUnread ? theme.surfaceElevated.opacity(skin.opacity.o32) : .clear
    }

    @ViewBuilder
    private var icon: some View {
        if let identity = identities.identity(for: event.source) {
            AinkradAppTile(symbol: identity.symbol, size: skin.size.s28)
                .allowsHitTesting(false)
        } else {
            Image(systemName: SignalPresentation.iconSymbol(for: event.severity))
                .font(skin.font(AinkradFontToken(sizeKey: "t15", weight: "medium", scaled: false)))
                .foregroundStyle(accent)
                .frame(width: skin.size.s28, height: skin.size.s28)
        }
    }

    private var titleLine: some View {
        HStack(spacing: AinkradSpacing.xs + 1) {
            if let symbol = event.deepLink?.symbol {
                Image(systemName: symbol)
                    .font(skin.font(AinkradFontToken(sizeKey: "t10", weight: "semibold", scaled: false)))
                    .foregroundStyle(theme.accentSecondary)
            }
            Text(event.title)
                .font(AinkradFont.display(12, weight: isUnread ? .semibold : .medium))
                .foregroundStyle(theme.foreground.opacity(isUnread ? 1 : skin.opacity.o78))
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
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o40))
            if overflowing || expanded {
                AinkradIconButton(
                    systemName: expanded ? "chevron.up" : "chevron.down", size: skin.size.s14,
                    tooltip: expanded ? "Show less" : "Show the whole message"
                ) {
                    expanded.toggle()
                }
            }
            Circle()
                .fill(theme.accentSecondary)
                .frame(width: skin.size.s5, height: skin.size.s5)
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
            .foregroundStyle(theme.foreground.opacity(skin.opacity.o62))
    }

    private var actions: some View {
        HStack(spacing: AinkradSpacing.xs) {
            ForEach(event.actions.prefix(2), id: \.id) { action in
                iconButton(action.symbol ?? "arrow.up.forward.circle", help: action.label) {
                    onAction(event, action)
                }
            }
            if isUnread {
                iconButton("envelope.open", help: "Mark read") { onMarkRead(event) }
            }
            iconButton("trash", help: "Dismiss") { onDismiss(event) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        AinkradIconButton(systemName: symbol, size: skin.size.s20, tooltip: help, action: action)
            .accessibilityLabel(help)
    }
}
