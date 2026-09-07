import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Binds `SignalSettingsPane` to the live environment.
///
/// The pane itself takes everything as parameters so it stays renderable in a
/// snapshot; this is the one place that reaches into `AppEnvironment` for it.
struct NotificationsSettingsView: View {
    let center: SignalCenter

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SignalSettingsPane(
            center: center,
            sources: sources,
            subscriptionRows: rows,
            notificationSounds: environment.notificationSounds,
            displayName: { id in
                environment.registry.allApps.first { $0.id == id }?.displayName ?? id
            },
            kindActivity: { center.kindActivity(for: $0) },
            onApproveSubscriptions: { appID in
                guard let subscriptions = environment.signalSubscriptions else { return }
                subscriptions.approve(appID: appID)
                // Register immediately, so approving here takes effect without
                // a relaunch — the same promise revoking makes.
                if let app = environment.registry.allApps.first(where: { $0.id == appID }),
                   let factory = app.signalObserverFactory {
                    subscriptions.register(observer: factory(), appID: appID)
                }
            },
            onRevokeSubscriptions: { appID in
                environment.signalSubscriptions?.revoke(appID: appID)
                // The observer is left registered on purpose: `fanOut`
                // consults approval per event, so revocation is already
                // immediate, and unregistering would mean re-creating the
                // observer to approve again.
            })
    }

    /// Host and Sage always — they are always present and always able to speak
    /// — then every installed app that has actually emitted something.
    ///
    /// Not every installed app: a delivery control for a source that has never
    /// said a word teaches the user this list is furniture, and then they stop
    /// reading it on the day it matters.
    ///
    /// An app the user has already CONFIGURED is the exception, and is included
    /// however quiet it has been. Without it, a source muted from a feed row's
    /// context menu — or one whose history has since been evicted by retention
    /// — has no row here, so the mute is set, is doing its job, and cannot be
    /// found. That is the "notifications stopped working" report this whole
    /// section exists to prevent.
    private var sources: [SignalSource] {
        let configured = SignalSettingsPane.configuredSources(in: center.rules)
        let apps = environment.registry.allApps
            .map { (id: $0.id, name: $0.displayName) }
            .filter {
                center.hasEverEmitted(.app(appID: $0.id))
                    || configured.contains(.app(appID: $0.id))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [.host, .sage] + apps.map { SignalSource.app(appID: $0.id) }
    }

    /// Every app that has declared subscriptions, approved or not.
    ///
    /// Refused apps are listed too — "Leyline asked and I said no" is
    /// otherwise unrecoverable, since nothing else in the UI records a
    /// declaration the user declined.
    private var rows: [SubscriptionSettingsSection.Row] {
        guard let subscriptions = environment.signalSubscriptions else { return [] }
        return environment.registry.allApps
            .compactMap { app in
                let declared = subscriptions.declared(for: app.id)
                guard !declared.isEmpty else { return nil }
                return SubscriptionSettingsSection.Row(
                    id: app.id,
                    appName: app.displayName,
                    subscriptions: declared,
                    isApproved: subscriptions.isApproved(appID: app.id))
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
}
