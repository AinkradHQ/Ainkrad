import Foundation
import UserNotifications
import AinkradSignal

@MainActor protocol BannerPosting: AnyObject {
    func post(_ event: SignalEvent)
}

/// macOS banner delivery. Authorization is requested lazily on the first
/// banner-routed event, not at launch, so the user is not prompted before there
/// is anything to show — the behaviour the old run notifier established and
/// this generalizes.
///
/// As of generation 9 this channel is the ONLY thing that posts a macOS banner,
/// including for completed agent runs. There is no second path any more, so a
/// bug here is a notification the user never sees rather than one they see
/// twice.
@MainActor
final class UserNotificationBannerChannel: BannerPosting {
    private var didRequestAuthorization = false

    nonisolated static let categoryPrefix = "com.ainkrad.signal.actions"

    /// Buttons are resolved from the notification's CATEGORY at delivery time,
    /// and a category carries a fixed action list — so a single shared category
    /// would give every banner the same two buttons. One category per
    /// `(source, kind)` is the smallest key whose action list is stable, and it
    /// keeps the registered set bounded by the vocabulary rather than by the
    /// number of events.
    nonisolated static func categoryID(for event: SignalEvent) -> String {
        "\(categoryPrefix).\(sourceSlug(event.source)).\(event.kind)"
    }

    /// Two, because macOS shows two inline buttons and folds the rest into a
    /// menu the user has to go looking for. A notification is not a place to
    /// go looking.
    nonisolated static func bannerActions(for event: SignalEvent) -> [UNNotificationAction] {
        event.actions.prefix(2).map { action in
            UNNotificationAction(identifier: action.id, title: action.label,
                                 options: action.isDestructive ? [.destructive] : [])
        }
    }

    /// Pure, so the shape of a banner is testable without authorization, a
    /// live center, or a running app — none of which a test has.
    nonisolated static func content(for event: SignalEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = event.title
        if let body = event.body { content.body = body }
        content.userInfo = ["signalEventID": event.id.uuidString]
        // Urgent means the user is BLOCKED on this. That is the one case worth
        // asking the system to break through Focus for, and `.timeSensitive` is
        // precisely that request — not a louder banner, a permission.
        content.interruptionLevel = event.proposedImportance == .urgent
            ? .timeSensitive : .active
        // The feed coalesces on the dedupe key; Notification Center coalesces
        // on the thread. Using the same string makes the two agree, so the
        // nineteen Raven warnings that are one row here are one thread there.
        content.threadIdentifier = event.dedupeKey
            ?? "\(sourceSlug(event.source)):\(event.kind)"
        if !event.actions.isEmpty { content.categoryIdentifier = categoryID(for: event) }
        return content
    }

    /// Stable and machine-shaped, deliberately not `SignalPresentation
    /// .sourceLabel`: that is a display string and may be localised or
    /// prettified, and a thread identifier that changes when a label changes
    /// silently splits an existing thread in two.
    nonisolated private static func sourceSlug(_ source: SignalSource) -> String {
        switch source {
        case .host: return "host"
        case .sage: return "sage"
        case .app(let id): return "app:\(id)"
        @unknown default: return "host"
        }
    }

    func post(_ event: SignalEvent) {
        requestAuthorizationIfNeeded()
        // Everything below runs inside the callbacks rather than being built
        // here and captured. `UNMutableNotificationContent` is not Sendable, so
        // handing one to a non-isolated completion is a Swift 6 region-isolation
        // error — and the original code's shape was already the answer to it.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let actions = Self.bannerActions(for: event)
            guard !actions.isEmpty else {
                Self.submit(event: event)
                return
            }
            // Registered immediately before the post it serves. macOS resolves
            // a banner's buttons from its category at DELIVERY time, so a
            // category registered afterwards leaves the banner already on
            // screen with no buttons and reports no error anywhere — the
            // failure mode is silence.
            let center = UNUserNotificationCenter.current()
            center.getNotificationCategories { existing in
                let category = UNNotificationCategory(
                    identifier: Self.categoryID(for: event), actions: actions,
                    intentIdentifiers: [], options: [])
                center.setNotificationCategories(
                    existing.filter { $0.identifier != category.identifier }
                        .union([category]))
                Self.submit(event: event)
            }
        }
    }

    nonisolated private static func submit(event: SignalEvent) {
        let request = UNNotificationRequest(identifier: event.id.uuidString,
                                            content: content(for: event), trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in
            // Best-effort: a failed banner never surfaces as an error. The
            // feed row exists regardless, which is the durable record.
        }
    }

    /// Pulls delivered banners for events the user has already dealt with
    /// in-app. Without it, reading a row in the feed leaves its banner sitting
    /// in Notification Center as an unread thing that is not unread.
    nonisolated static func withdraw(ids: [UUID]) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ids.map(\.uuidString))
    }

    private func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Re-checked per post via getNotificationSettings; nothing to cache.
        }
    }
}
