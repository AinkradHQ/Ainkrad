import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Ainkrad → Notifications. Every change writes straight through to
/// `SignalCenter`, whose `didSet` hooks persist it — no Save button, matching
/// the rest of Settings.
struct SignalSettingsPane: View {
    let center: SignalCenter
    var sources: [SignalSource] = [.host, .sage]
    /// Cross-app access rows, or empty when no app has ever asked. Passed in
    /// rather than read from the environment so the pane stays renderable in a
    /// snapshot.
    var subscriptionRows: [SubscriptionSettingsSection.Row] = []
    /// Nil in a snapshot, where there is no bootstrap and so no engine — the
    /// panel is then simply absent rather than bound to a stand-in that lies
    /// about what the app will do.
    var notificationSounds: NotificationSoundStore?
    var displayName: (String) -> String = { $0 }

    /// An app's real display name where the host knows it, falling back to the
    /// kit's label. `SignalPresentation.sourceLabel` only capitalises the bundle
    /// id's last component, which turns "gitmage" into "Gitmage".
    /// Kinds this source has emitted. Supplied by the binding view; empty is a
    /// legitimate state and the sheet omits the section for it.
    var kindActivity: (SignalSource) -> [SignalKindActivity] = { _ in [] }

    /// Every source the rules say something about, whether or not it has ever
    /// emitted.
    ///
    /// The pane's source list is deliberately filtered by `hasEverEmitted` — a
    /// delivery control for a source that has never spoken teaches the user the
    /// list is furniture. But a source the user has already CONFIGURED is not
    /// furniture: they made that setting and must be able to find it again.
    /// Every rule that can name a source contributes here, so adding a new one
    /// to `RoutingRules` and forgetting this is a compile-visible omission
    /// rather than a setting that quietly becomes unreachable.
    static func configuredSources(in rules: RoutingRules) -> Set<SignalSource> {
        var out = rules.mutedSources
        out.formUnion(rules.sourceOverrides.keys)
        out.formUnion(rules.sourceKindOverrides.keys.map(\.source))
        out.formUnion(rules.interruptFloor.keys)
        out.formUnion(rules.soundOverride.keys)
        out.formUnion(rules.urgentBypass)
        return out
    }

    private func displayName(for source: SignalSource) -> String {
        if case .app(let id) = source { return displayName(id) }
        return SignalPresentation.sourceLabel(source)
    }
    var onApproveSubscriptions: (String) -> Void = { _ in }
    var onRevokeSubscriptions: (String) -> Void = { _ in }

    @Environment(\.ainkradTheme) private var theme
    @State private var confirmingClear = false
    /// Which source's detail is open. One at a time: several expanded at once
    /// turns the list into a wall and loses the comparison it exists for.
    @State private var expanded: SignalSource?
    @State private var healthWindow: NotificationHealthPanel.Window = .week
    /// Closed by default. Retention limits, the stats readout and cross-app
    /// access are all things a user consults, not things they set — and at full
    /// weight they made the pane read as a control panel.
    @State private var showsAdvanced = false

    /// One health computation per render, not one per row.
    private var health: SignalHealth {
        center.health(since: Date().addingTimeInterval(-healthWindow.seconds))
    }

    /// The noisiest kind for each source in the current window, for the status
    /// lines. Built once here because `noisiest` is already sorted loudest
    /// first, so the first entry per source is that source's own worst.
    private func loudestBySource(_ health: SignalHealth) -> [SignalSource: SignalKindActivity] {
        var out: [SignalSource: SignalKindActivity] = [:]
        for entry in health.noisiest {
            guard let source = entry.source, out[source] == nil else { continue }
            out[source] = entry
        }
        return out
    }

    var body: some View {
        let health = self.health
        let loudest = loudestBySource(health)

        return VStack(alignment: .leading, spacing: 14) {
            // The invariant, stated ONCE. It used to be repeated in the
            // Delivery hint and again inside the per-source sheet, because
            // "Feed only" and "Off" both needed explaining. "Quiet" carries it,
            // so one line at the top is enough.
            AinkradCaption("Alert interrupts you · Quiet is recorded only · Off silences "
                           + "every channel. Everything reaches the feed either way — "
                           + "the log is not optional.")

            GlobalNotificationSettings(
                rules: Binding(get: { center.rules }, set: { center.rules = $0 }),
                sounds: notificationSounds)

            sourcesPanel(loudest: loudest)

            advancedPanel(health: health)
        }
        .confirmationDialog("Clear the notification feed?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { center.clearFeed() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned events are kept. This cannot be undone.")
        }
    }

    /// One row per source, and the one place a source's settings are shown.
    private func sourcesPanel(
        loudest: [SignalSource: SignalKindActivity]
    ) -> some View {
        AinkradSettingsPanel(
            title: "Sources",
            hint: "What each source may interrupt you with."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                // Keyed on the source, not its position. `sources` is
                // recomputed from live state, so the first time an app emits
                // the list re-orders — and with index identity `expanded`
                // then pointed at a different row and the expansion
                // cross-faded the wrong content.
                ForEach(sources, id: \.self) { source in
                    sourceRow(source, loudest: loudest[source])
                    if expanded == source {
                        SourceNotificationSheet(
                            source: source,
                            sourceName: displayName(for: source),
                            rules: Binding(get: { center.rules },
                                           set: { center.rules = $0 }),
                            activity: kindActivity(source))
                        .padding(.leading, AinkradSpacing.md)
                    }
                }

                if !SignalSettingsPane.configuredSources(in: center.rules).isEmpty {
                    HStack {
                        Spacer()
                        // The bulk escape hatch. Individual overrides are
                        // removed at the control that produced them — the
                        // picker on the row, or a kind in the detail — which
                        // is why the standalone "Muted" panel is gone.
                        AinkradButton(title: "Reset all overrides", style: .ghost) {
                            // Only the per-source and per-kind settings. Quiet
                            // hours and the sound switch are not overrides and
                            // must survive: a user clearing their app settings
                            // has not asked to be woken at 3am.
                            center.rules.mutedSources.removeAll()
                            center.rules.sourceOverrides.removeAll()
                            center.rules.sourceKindOverrides.removeAll()
                            center.rules.interruptFloor.removeAll()
                            center.rules.soundOverride.removeAll()
                            center.rules.urgentBypass.removeAll()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: SignalSource,
                           loudest: SignalKindActivity?) -> some View {
        AinkradCaptionedRow(displayName(for: source)) {
            HStack(spacing: AinkradSpacing.sm) {
                AinkradSegmentedPicker(
                    items: SignalDeliveryMode.allCases,
                    selection: Binding(
                        get: { SignalDeliveryMode(rules: center.rules, source: source) },
                        set: { $0.apply(to: &center.rules, source: source) }),
                    label: \.label)
                // Expands in place rather than opening a modal: the user is
                // comparing sources, and a sheet that covers the list they are
                // comparing makes that harder for no gain.
                AinkradButton(title: expanded == source ? "Done" : "More…",
                              style: .ghost) {
                    expanded = expanded == source ? nil : source
                }
            }
        }
        // Everything the row's own picker does NOT say: quiet kinds, a floor, a
        // cue, a bypass, and the kind that is currently shouting. This is what
        // retired the separate summary panel — the truth now sits beside the
        // control that produced it.
        if let status = SourceStatusLine.text(rules: center.rules, source: source,
                                              loudest: loudest) {
            Text(status)
                .font(AinkradFont.mono(9.5))
                .foregroundStyle(theme.foreground.opacity(0.5))
                .padding(.leading, AinkradSpacing.md)
        }
    }

    /// Consulted, not set. Everything here was previously at the same visual
    /// weight as quiet hours.
    private func advancedPanel(health: SignalHealth) -> some View {
        AinkradSettingsPanel(title: "Advanced") {
            AinkradDisclosureGroup(title: "Retention, stats and access",
                                   isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: 14) {
                    retention
                    NotificationHealthPanel(window: $healthWindow, health: health)
                    // Only when something has asked. An empty permissions panel
                    // on every install teaches the user that this section is
                    // furniture, and then they stop reading it on the day it
                    // matters.
                    if !subscriptionRows.isEmpty {
                        VStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                            AinkradCaption("Apps that asked to read another app's "
                                           + "notifications. Revoking takes effect "
                                           + "immediately; the app keeps working.")
                            SubscriptionSettingsSection(rows: subscriptionRows,
                                                        displayName: displayName,
                                                        onApprove: onApproveSubscriptions,
                                                        onRevoke: onRevokeSubscriptions)
                        }
                    }
                }
            }
        }
    }

    private var retention: some View {
        VStack(alignment: .leading, spacing: 9) {
            AinkradCaption("The feed keeps the most recent events and drops the rest. "
                           + "Pinned events are never dropped and do not count toward "
                           + "the limit.")
            AinkradCaptionedRow("Keep for (days)") {
                AinkradStepper(value: Binding(
                    get: { center.retention.maxAgeDays },
                    set: { center.retention.maxAgeDays = $0 }), in: 1...365)
            }
            AinkradCaptionedRow("Maximum events") {
                AinkradStepper(value: Binding(
                    get: { center.retention.maxEvents },
                    set: { center.retention.maxEvents = $0 }), in: 100...100_000, step: 100)
            }
            HStack {
                // A count is a readout, so mono.
                Text("\(center.eventCount) events stored")
                    .font(AinkradFont.mono(10.5))
                    .foregroundStyle(theme.foreground.opacity(0.5))
                Spacer()
                AinkradButton(title: "Clear feed", style: .danger) {
                    confirmingClear = true
                }
            }
        }
    }
}
