import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The overlay layers `RootView.body` stacks above the workspace: the
/// plugin overlay, the notification overlays and the toasts. Computed views
/// only — every piece of state stays on `RootView`.
extension RootView {
    /// The floating overlay for an `.overlay`-presentation app.
    ///
    /// Its own property rather than inline in `body`: adding the `mode`
    /// argument pushed that already-large view builder past the type-checker's
    /// budget ("unable to type-check this expression in reasonable time").
    @ViewBuilder
    var pluginOverlay: some View {
        if let id = environment.presentedOverlayAppID,
            let app = environment.registry.allApps.first(where: { $0.id == id })
        {
            let mode = environment.appAppearanceStore.effectiveMode(for: app)
            let size = environment.appAppearanceStore.effectiveOverlaySize(app.id)
            PluginOverlayView(
                app: app, tokens: environment.themeManager.tokens,
                mode: mode, size: size
            ) {
                environment.presentedOverlayAppID = nil
            }
            .transition(.opacity)
        }
    }

    /// The feed's overlays: the bell dropdown and the full feed.
    ///
    /// Extracted from the main `ZStack` because that body outgrew the type
    /// checker once these were added — SwiftUI's inference cost is
    /// superlinear in a single builder, so a large ZStack must be split rather
    /// than grown.
    @ViewBuilder
    var signalOverlays: some View {
        if environment.isSignalDropdownPresented, let center = environment.signalCenter {
            // Anchored below the top bar on the trailing edge, under the bell
            // that opened it. Presented here rather than as an overlay on
            // `HUDBar`, because that strip is 30pt tall and would clip it.
            SignalBellDropdownOverlay(center: center, hub: environment.signalEmitterHub) {
                environment.isSignalDropdownPresented = false
            } onViewAll: {
                environment.isSignalDropdownPresented = false
                environment.isSignalFeedPresented = true
            } onOpenSettings: {
                environment.isSignalDropdownPresented = false
                environment.isSettingsPresented = true
            }
            .environment(\.ainkradSignalIdentity, signalIdentities)
            .zIndex(60)
        }

        // The consent prompt. Raised as a HUD overlay rather than inline in the
        // App Store's install flow, because an install is not the only way an
        // app arrives — `ainkrad dev`, a sideload and a catalog update all end
        // with a declared subscription nobody has answered, and a prompt that
        // only existed in the store flow would silently skip all three.
        //
        // Below the first-run gate and the quit confirmation, like every other
        // dismissible overlay: a permission prompt floating over the gate
        // would be the one surface the scrim cannot cover.
        if let appID = environment.pendingSubscriptionApprovals.first,
            let subscriptions = environment.signalSubscriptions,
            let app = environment.registry.allApps.first(where: { $0.id == appID })
        {
            SubscriptionApprovalView(
                appName: app.displayName,
                subscriptions: subscriptions.declared(for: appID),
                displayName: { id in
                    environment.registry.allApps.first { $0.id == id }?.displayName ?? id
                },
                // True when this app was approved before and has widened its
                // list. `isApproved` is false either way, so the flag comes
                // from whether anything was ever approved for it.
                isReapproval: subscriptions.hasEverBeenApproved(appID: appID),
                onAllow: {
                    subscriptions.approve(appID: appID)
                    if let factory = app.signalObserverFactory {
                        subscriptions.register(observer: factory(), appID: appID)
                    }
                    environment.pendingSubscriptionApprovals.removeFirst()
                },
                onDeny: {
                    // Nothing is recorded as denied: the app simply stays
                    // unapproved, which is the same state it was in before
                    // asking. Storing a "denied" verdict would mean deciding
                    // when to ask again, and the honest answer — when the app
                    // changes what it wants — is exactly what an absent
                    // approval already expresses.
                    subscriptions.revoke(appID: appID)
                    environment.pendingSubscriptionApprovals.removeFirst()
                }
            )
            .transition(.opacity)
            .zIndex(70)
        }

        if environment.isSignalFeedPresented, let center = environment.signalCenter {
            SignalFeedOverlayView(
                center: center,
                hub: environment.signalEmitterHub,
                onDismiss: { environment.isSignalFeedPresented = false },
                viewStateStore: environment.signalViewStateStore,
                // The rail's "Notification settings…" lands in Settings, on the
                // Notifications page, rather than opening a second control
                // surface that would then disagree with the first.
                onConfigureSource: { _ in
                    environment.isSignalFeedPresented = false
                    environment.isSettingsPresented = true
                }
            )
            // Scale from just under, like every other summoned HUD panel,
            // rather than the bare cross-fade it had: a fade alone reads as a
            // web modal, and the feed is the largest surface in the family.
            .transition(
                reduceMotion
                    ? .opacity
                    : .scale(scale: 0.97).combined(with: .opacity))
        }
    }

    /// Who sent each notification, from the live app registry: the name and
    /// launcher symbol the user knows the app by. Rebuilt with the view, so an
    /// app installed or renamed shows up on the next notification.
    var signalIdentities: SignalIdentityResolver {
        SignalIdentityResolver(
            apps: Dictionary(
                environment.registry.allApps.map {
                    ($0.id, SignalSourceIdentity(name: $0.displayName, symbol: $0.icon))
                }, uniquingKeysWith: { first, _ in first }),
            host: SignalSourceIdentity(name: "Ainkrad", symbol: "sparkle"))
    }

    /// Transient toasts, top-trailing under the bell that counts them.
    ///
    /// Above the workspace and every dismissible overlay, but deliberately
    /// BELOW the first-run gate (zIndex 100) and the quit confirmation (200): a
    /// toast floating over the gate would be another surface the scrim cannot
    /// cover.
    var signalToasts: some View {
        SignalToastStack(
            model: environment.signalToasts,
            now: Date(),
            onActivate: { event in
                guard let center = environment.signalCenter else { return }
                // Go to the source, not to the feed. A toast names one specific
                // thing; sending the user to a list of everything makes them
                // find it again. Only an event with nowhere to go falls back.
                center.activate(event)
                if !event.hasDestination { environment.isSignalFeedPresented = true }
                // Acted on, so it goes: a toast still sitting there after it
                // took you somewhere reads as though the tap did nothing.
                environment.signalToasts.dismiss(id: event.id)
            },
            onAction: { event, action in
                let hub = environment.signalEmitterHub
                if action.isDestructive {
                    // A destructive action never fires straight off a toast:
                    // the user clicked something that appeared over their work,
                    // not a confirmation. The feed owns the dialog.
                    environment.signalToasts.dismiss(id: event.id)
                    environment.isSignalFeedPresented = true
                    return
                }
                SignalActionRouter(hub: hub).dispatch(event, action)
                environment.signalToasts.dismiss(id: event.id)
            }
        )
        .environment(\.ainkradSignalIdentity, signalIdentities)
        // Clear of the 30pt top bar, so a toast never covers the clock or the
        // bell whose count it corresponds to.
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(!environment.isSetupPresented)
        .zIndex(50)
    }
}
