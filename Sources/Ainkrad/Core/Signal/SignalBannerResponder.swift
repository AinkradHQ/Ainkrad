import AppKit
import UserNotifications
import AinkradSignal

/// Turns a clicked macOS banner back into exactly what a clicked feed row does.
///
/// Before this existed, `BannerChannel` wrote the event's id into the
/// notification's `userInfo` and nothing ever read it: clicking a banner
/// activated the app and did nothing else. No feed, no mark-read, no deep link,
/// no pane focus. The away-from-keyboard path is where a notification carries
/// the most value, and it was the one surface from which the event's own
/// `deepLink` and `locator` could not be followed.
///
/// The delegate callback is a one-line forward to `handle(eventID:actionID:)`
/// because `UNNotificationResponse` cannot be constructed in a test. All the
/// behaviour worth testing lives in the plain method.
@MainActor
final class SignalBannerResponder: NSObject, UNUserNotificationCenterDelegate {
    private let center: SignalCenter

    /// Called when the named event is gone — retention evicted it, or the feed
    /// was cleared. Opening the feed is the honest answer: the user asked to see
    /// something, and "nothing happens" is precisely the behaviour this type
    /// exists to remove.
    var onOpenFeed: () -> Void = {}

    init(center: SignalCenter) {
        self.center = center
        super.init()
    }

    func handle(eventID: String, actionID: String?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let id = UUID(uuidString: eventID), let event = center.event(id: id) else {
            onOpenFeed()
            return
        }
        if let actionID, actionID != UNNotificationDefaultActionIdentifier,
           actionID != UNNotificationDismissActionIdentifier,
           let action = event.actions.first(where: { $0.id == actionID }) {
            center.markRead(ids: [event.id])
            center.invokeBannerAction(action, on: event)
            return
        }
        // The dismiss action is the user swiping the banner away. That is not a
        // request to go anywhere — marking it read is right, opening a window
        // over whatever they were doing is not.
        if actionID == UNNotificationDismissActionIdentifier {
            center.markRead(ids: [event.id])
            return
        }
        // `activate` marks read and follows the deep link — the same method the
        // dropdown and the overlay call, so all three surfaces cannot drift.
        center.activate(event)
        // Nowhere to go: show the user the record instead of appearing to
        // ignore the click.
        if !event.hasDestination { onOpenFeed() }
    }

    /// `nonisolated` deliberately: `UNUserNotificationCenter` calls its delegate
    /// off the main actor. A method that inherited `@MainActor` here would trap
    /// on Swift's isolation assertion — the same failure that killed the socket
    /// server's `DispatchSource` handlers mid-suite and left the run reporting
    /// "passed" for the handful of tests that had already finished.
    nonisolated func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let eventID = response.notification.request.identifier
        let actionID = response.actionIdentifier
        Task { @MainActor in self.handle(eventID: eventID, actionID: actionID) }
        // Called here rather than inside the Task: the closure is not Sendable,
        // so handing it to a main-actor task is a region-isolation error. It
        // only tells the system we have taken delivery of the response — the
        // routing itself continues on the main actor, which is where every
        // other Signal surface already does its work.
        completionHandler()
    }
}
