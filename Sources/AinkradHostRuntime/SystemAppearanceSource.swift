import Foundation

/// Where `ThemeManager` reads the macOS light/dark setting. Tests pass a stub.
@MainActor
public protocol SystemAppearanceSource: AnyObject {
    var current: ThemeAppearance { get }
    /// `handler` runs on the main actor after every system appearance change.
    func observe(_ handler: @escaping @MainActor () -> Void)
}

/// The real system setting. Not `NSApp.effectiveAppearance`: the host pins
/// `NSApp.appearance`, after which that reports the pinned value, not the system's.
@MainActor
public final class LiveSystemAppearance: SystemAppearanceSource {
    private var token: NSObjectProtocol?

    public init() {}

    public var current: ThemeAppearance {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }

    public func observe(_ handler: @escaping @MainActor () -> Void) {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { handler() } }
    }

    isolated deinit {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
    }
}
