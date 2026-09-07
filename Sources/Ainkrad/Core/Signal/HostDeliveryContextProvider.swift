import AppKit
import AinkradSignal

/// Reads the user's actual situation. The single place the host answers
/// "is the user looking?" - the input that turns a toast into a banner.
@MainActor
final class HostDeliveryContextProvider: SignalContextProviding {
    /// Supplied by the host so this type does not reach into window management.
    var visibleAppIDs: () -> Set<String> = { [] }
    var hostFocusMode: () -> Bool = { false }

    var deliveryContext: DeliveryContext {
        DeliveryContext(
            hostIsFrontmost: NSApplication.shared.isActive,
            visibleAppIDs: visibleAppIDs(),
            systemDoNotDisturb: Self.doNotDisturbIsOn,
            hostFocusMode: hostFocusMode())
    }

    /// macOS exposes no public API for the Focus state. `UNUserNotificationCenter`
    /// enforces Focus itself when a banner is posted, so treating it as off here
    /// is correct rather than merely convenient: the system is the authority for
    /// banners, and suppressing `.sound` on a guess would silence alerts the
    /// user did not silence. Revisit only if a public API appears.
    private static var doNotDisturbIsOn: Bool { false }
}
