import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import AinkradSignal
import SwiftUI

/// Notifications as DECLARED tabs: When (quiet hours, snooze, sound), Sources
/// (one row per source, then one editor for a source's kinds and fine
/// tuning), Feed (retention, stats, clear) and Access (cross-app reads).
@MainActor
extension HostSettingsCatalog {
    static func notificationGroups(
        _ environment: AppEnvironment, center: SignalCenter,
        page: SettingsPath
    ) -> [SettingsGroup] {
        [
            whenGroup(environment, center, page.appending("when")),
            sourcesGroup(environment, center, page.appending("sources")),
            feedGroup(environment, center, page.appending("feed")),
        ]
            + accessGroup(environment, page.appending("access"))
    }

    private static func rules(_ center: SignalCenter) -> (@escaping (inout RoutingRules) -> Void) -> Void {
        { change in
            var r = center.rules
            change(&r)
            center.rules = r
        }
    }

    // MARK: - When

    private static func whenGroup(
        _ environment: AppEnvironment, _ center: SignalCenter,
        _ group: SettingsPath
    ) -> SettingsGroup {
        let update = rules(center)
        let suppression = center.rules.suppression
        let hours = (0...23).map { SettingsOption(id: "\($0)", title: String(format: "%02d:00", $0)) }
        func hour(_ key: WritableKeyPath<SuppressionWindow, Int?>, _ label: String) -> SettingsField {
            SettingsField(
                path: group.appending(label.lowercased()), label: label,
                kind: .select(
                    options: hours,
                    selection: Binding(
                        get: { "\((center.rules.suppression[keyPath: key] ?? 0) / 60)" },
                        set: { v in update { $0.suppression[keyPath: key] = (Int(v) ?? 0) * 60 } })))
        }
        var fields = [
            SettingsField(
                path: group.appending("schedule"), label: "Quiet hours",
                help: "Defers interruptions without losing anything — events are still recorded.",
                keywords: ["quiet", "schedule", "do not disturb", "night"],
                kind: .toggle(
                    Binding(
                        get: { center.rules.suppression.quietStartMinute != nil },
                        set: { on in
                            update {
                                $0.suppression.quietStartMinute = on ? 22 * 60 : nil
                                $0.suppression.quietEndMinute = on ? 7 * 60 : nil
                            }
                        })))
        ]
        if suppression.quietStartMinute != nil {
            fields += [
                hour(\.quietStartMinute, "From"), hour(\.quietEndMinute, "Until"),
                SettingsField(
                    path: group.appending("mode"), label: "During quiet hours",
                    kind: .select(
                        options: [
                            SettingsOption(id: "everything", title: "Nothing interrupts"),
                            SettingsOption(id: "sound", title: "Silent, but still visible"),
                        ],
                        selection: Binding(
                            get: { center.rules.suppression.mode == .soundOnly ? "sound" : "everything" },
                            set: { v in update { $0.suppression.mode = v == "sound" ? .soundOnly : .everything } }))),
            ]
        }
        let now = Date()
        let snoozed = suppression.snoozedUntil.map { $0 > now } ?? false
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        fields.append(
            SettingsField(
                path: group.appending("snooze"), label: "Snooze",
                help: snoozed
                    ? "Quiet until \(time.string(from: suppression.snoozedUntil!))."
                    : "Pause interruptions for a while.",
                keywords: ["snooze", "pause", "quiet"],
                kind: .select(
                    options: (snoozed
                        ? [
                            SettingsOption(
                                id: "snoozed", title: "Quiet until \(time.string(from: suppression.snoozedUntil!))"),
                            SettingsOption(id: "off", title: "Resume now"),
                        ]
                        : [SettingsOption(id: "off", title: "Not snoozed")])
                        + SignalSnooze.allCases.map { SettingsOption(id: $0.rawValue, title: $0.label) },
                    selection: Binding(
                        get: { snoozed ? "snoozed" : "off" },
                        set: { v in
                            guard v != "snoozed" else { return }
                            update {
                                if let snooze = SignalSnooze(rawValue: v) {
                                    snooze.apply(to: &$0.suppression, at: Date())
                                } else {
                                    SignalSnooze.lift(&$0.suppression)
                                }
                            }
                        }))))
        if let sounds = environment.notificationSounds {
            fields += [
                SettingsField(
                    path: group.appending("sound"), label: "Play a sound",
                    help: "Separate from interface sounds — turning those off will not silence a failure.",
                    keywords: ["sound", "chime", "notification sound"],
                    kind: .toggle(Binding(get: { sounds.settings.isEnabled }, set: { sounds.settings.isEnabled = $0 }))),
                SettingsField(
                    path: group.appending("volume"), label: "Volume",
                    help: "\(Int(sounds.settings.volume * 100))%",
                    kind: .slider(
                        range: 0...1, step: 0.05,
                        value: Binding(
                            get: { sounds.settings.volume }, set: { sounds.settings.volume = $0 }))),
            ]
        }
        return SettingsGroup(
            path: group, title: "When",
            footerNote: "Quiet hours defer interruptions, they do not lose information — events "
                + "are still recorded and unread counts still move.",
            fields: fields)
    }

    // MARK: - Sources

    private static func notificationSources(_ environment: AppEnvironment, _ center: SignalCenter) -> [SignalSource] {
        let configured = center.rules.configuredSources
        let apps = environment.registry.allApps
            .filter { center.hasEverEmitted(.app(appID: $0.id)) || configured.contains(.app(appID: $0.id)) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return [.host, .sage] + apps.map { SignalSource.app(appID: $0.id) }
    }

    private static func sourceName(_ environment: AppEnvironment, _ source: SignalSource) -> String {
        if case .app(let id) = source {
            return environment.registry.allApps.first { $0.id == id }?.displayName ?? id
        }
        return SignalPresentation.sourceLabel(source)
    }

    private static func sourceKey(_ source: SignalSource) -> String {
        switch source {
        case .app(let id): "app.\(id)"
        default: SignalPresentation.sourceLabel(source).lowercased()
        }
    }

    private static func sourcesGroup(
        _ environment: AppEnvironment, _ center: SignalCenter,
        _ group: SettingsPath
    ) -> SettingsGroup {
        let update = rules(center)
        let drafts = environment.settingsDrafts
        let sources = notificationSources(environment, center)
        let health = center.health(since: Date().addingTimeInterval(-drafts.healthWindow.seconds))
        var loudest: [SignalSource: SignalKindActivity] = [:]
        for entry in health.noisiest { if let s = entry.source, loudest[s] == nil { loudest[s] = entry } }

        var fields: [SettingsField] = sources.map { source in
            SettingsField(
                path: group.appending(sourceKey(source)), label: sourceName(environment, source),
                help: SourceStatusLine.text(rules: center.rules, source: source, loudest: loudest[source]),
                keywords: ["notification", "source", sourceName(environment, source).lowercased()],
                kind: .select(
                    options: SignalDeliveryMode.allCases.map { SettingsOption(id: $0.rawValue, title: $0.label) },
                    selection: Binding(
                        get: { SignalDeliveryMode(rules: center.rules, source: source).rawValue },
                        set: { v in
                            if let m = SignalDeliveryMode(rawValue: v) { update { m.apply(to: &$0, source: source) } }
                        })))
        }
        if !center.rules.configuredSources.isEmpty {
            fields.append(
                SettingsField(
                    path: group.appending("reset"), label: "Reset all overrides",
                    help: "Every source back to its default.",
                    kind: .action(title: "Reset") {
                        update {
                            $0.mutedSources.removeAll()
                            $0.sourceOverrides.removeAll()
                            $0.sourceKindOverrides.removeAll()
                            $0.interruptFloor.removeAll()
                            $0.soundOverride.removeAll()
                            $0.urgentBypass.removeAll()
                        }
                    }))
        }

        // The editor: one source's kinds and fine tuning.
        fields.append(
            SettingsField(
                path: group.appending("details"), label: "Details for",
                help: "What a source tells you, kind by kind, and its fine tuning.",
                keywords: ["notification", "kind", "fine tuning", "floor", "urgent"],
                kind: .select(
                    options: [SettingsOption(id: "", title: "Choose a source…")]
                        + sources.map { SettingsOption(id: sourceKey($0), title: sourceName(environment, $0)) },
                    selection: Binding(get: { drafts.notificationSource }, set: { drafts.notificationSource = $0 }))))
        if let source = sources.first(where: { sourceKey($0) == drafts.notificationSource }) {
            let detail = group.appending("detail")
            let activity = center.kindActivity(for: source)
            if activity.isEmpty {
                fields.append(
                    SettingsField(
                        path: detail.appending("none"), label: "Kinds",
                        help: "Nothing recorded from \(sourceName(environment, source)) yet.",
                        kind: .shortcut(.constant("—"))))
            }
            fields += activity.map { entry in
                SettingsField(
                    path: detail.appending("kind-\(entry.kind)"), label: entry.kind,
                    help: entry.count == 1 ? "Once" : "\(entry.count) times",
                    keywords: ["notification", "kind", entry.kind.lowercased()],
                    kind: .select(
                        options: SignalDeliveryMode.kindOptions.map {
                            SettingsOption(id: $0.rawValue, title: $0.label)
                        },
                        selection: Binding(
                            get: { SignalDeliveryMode(rules: center.rules, source: source, kind: entry.kind).rawValue },
                            set: { v in
                                if let m = SignalDeliveryMode(rawValue: v) {
                                    update { m.apply(to: &$0, source: source, kind: entry.kind) }
                                }
                            })))
            }
            let sounds: [(String, SignalSoundChoice)] = [
                ("Match severity", .bySeverity), ("Silent", .silent),
                (UISound.confirm.displayName, .named(UISound.confirm.rawValue)),
                (UISound.error.displayName, .named(UISound.error.rawValue)),
            ]
            fields += [
                SettingsField(
                    path: detail.appending("floor"), label: "Interrupt me at",
                    help: "Below the floor, events go quiet — recorded, never interrupting.",
                    kind: .select(
                        options: SignalSeverity.allCases.map { SettingsOption(id: "\($0)", title: $0.floorLabel) },
                        selection: Binding(
                            get: { "\(center.rules.interruptFloor[source] ?? .info)" },
                            set: { v in
                                guard let floor = SignalSeverity.allCases.first(where: { "\($0)" == v }) else { return }
                                update { $0.interruptFloor[source] = floor == .info ? nil : floor }
                            }))),
                SettingsField(
                    path: detail.appending("sound"), label: "Sound",
                    kind: .select(
                        options: sounds.map { SettingsOption(id: $0.0, title: $0.0) },
                        selection: Binding(
                            get: {
                                sounds.first { $0.1 == (center.rules.soundOverride[source] ?? .bySeverity) }?.0
                                    ?? "Match severity"
                            },
                            set: { v in
                                guard let choice = sounds.first(where: { $0.0 == v })?.1 else { return }
                                update { $0.soundOverride[source] = choice == .bySeverity ? nil : choice }
                            }))),
                SettingsField(
                    path: detail.appending("urgent"), label: "Let urgent through quiet hours and Focus",
                    help: "Only events the app marks urgent — something waiting on you, not its usual chatter.",
                    kind: .toggle(
                        Binding(
                            get: { center.rules.urgentBypass.contains(source) },
                            set: { on in
                                update {
                                    if on { $0.urgentBypass.insert(source) } else { $0.urgentBypass.remove(source) }
                                }
                            }))),
            ]
        }
        return SettingsGroup(
            path: group, title: "Sources",
            footerNote: "Alert interrupts you · Quiet is recorded only · Off silences every "
                + "channel. Everything reaches the feed either way.",
            fields: fields)
    }

    // MARK: - Feed

    private static func feedGroup(
        _ environment: AppEnvironment, _ center: SignalCenter,
        _ group: SettingsPath
    ) -> SettingsGroup {
        let drafts = environment.settingsDrafts
        let health = center.health(since: Date().addingTimeInterval(-drafts.healthWindow.seconds))
        let stats =
            health.total < 5
            ? "Not enough history yet."
            : "\(health.total) arrived · \(NotificationStats.percent(health.readRate)) read · "
                + "median reply \(NotificationStats.duration(health.medianAcknowledgeSeconds))"
        return SettingsGroup(
            path: group, title: "Feed",
            footerNote: "The feed keeps the most recent events and drops the rest. Pinned events are never "
                + "dropped and don't count toward the limit.",
            fields: [
                SettingsField(
                    path: group.appending("days"), label: "Keep for",
                    help: "\(center.retention.maxAgeDays) days",
                    keywords: ["retention", "days", "history"],
                    kind: .slider(
                        range: 1...365, step: 1,
                        value: Binding(
                            get: { Double(center.retention.maxAgeDays) },
                            set: { center.retention.maxAgeDays = Int($0) }))),
                SettingsField(
                    path: group.appending("max"), label: "Maximum events",
                    help: "\(center.retention.maxEvents) events",
                    keywords: ["retention", "limit", "events"],
                    kind: .slider(
                        range: 100...100_000, step: 100,
                        value: Binding(
                            get: { Double(center.retention.maxEvents) },
                            set: { center.retention.maxEvents = Int($0) }))),
                SettingsField(
                    path: group.appending("stats"), label: "Delivery stats",
                    help: "\(stats) — measured from your own feed, kept on this Mac.",
                    keywords: ["stats", "health", "read rate"],
                    kind: .select(
                        options: NotificationStats.Window.allCases.map {
                            SettingsOption(id: $0.rawValue, title: $0.label)
                        },
                        selection: Binding(
                            get: { drafts.healthWindow.rawValue },
                            set: { if let w = NotificationStats.Window(rawValue: $0) { drafts.healthWindow = w } }))),
                SettingsField(
                    path: group.appending("clear"), label: "Clear the feed",
                    help: "\(center.eventCount) events stored. Pinned events are kept.",
                    keywords: ["clear", "feed", "delete"],
                    kind: .action(title: "Clear…") {
                        if confirm(
                            "Clear the notification feed?", "Pinned events are kept. This cannot be undone.",
                            action: "Clear")
                        {
                            center.clearFeed()
                        }
                    }),
            ])
    }

    // MARK: - Access

    private static func accessGroup(_ environment: AppEnvironment, _ group: SettingsPath) -> [SettingsGroup] {
        guard let subscriptions = environment.signalSubscriptions else { return [] }
        let apps = environment.registry.allApps.compactMap { app -> (RegisteredApp, [SignalSubscription])? in
            let declared = subscriptions.declared(for: app.id)
            return declared.isEmpty ? nil : (app, declared)
        }
        guard !apps.isEmpty else { return [] }
        return [
            SettingsGroup(
                path: group, title: "Access",
                footerNote: "Apps that asked to read another app's notifications. Revoking takes effect "
                    + "immediately; the app keeps working.",
                fields: apps.map { app, declared in
                    SettingsField(
                        path: group.appending(app.id), label: app.displayName,
                        help: declared.map { s -> String in
                            let name: String
                            if let builtIn = s.builtInSourceName {
                                name = builtIn
                            } else if case .app(let id) = s.source {
                                name = sourceName(environment, .app(appID: id))
                            } else {
                                name = "Another app"
                            }
                            return "\(name): \(s.kindDescription)"
                        }.joined(separator: " · "),
                        keywords: ["access", "subscription", app.displayName.lowercased()],
                        kind: .select(
                            options: [
                                SettingsOption(id: "allowed", title: "Allowed"),
                                SettingsOption(id: "denied", title: "Not allowed"),
                            ],
                            selection: Binding(
                                get: { subscriptions.isApproved(appID: app.id) ? "allowed" : "denied" },
                                set: { v in
                                    if v == "allowed" {
                                        subscriptions.approve(appID: app.id)
                                        if let factory = app.signalObserverFactory {
                                            subscriptions.register(observer: factory(), appID: app.id)
                                        }
                                    } else {
                                        subscriptions.revoke(appID: app.id)
                                    }
                                })))
                })
        ]
    }
}
