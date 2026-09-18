import Foundation

/// Host-owned mailbox for app→app launches. Holds at most one pending payload
/// per target appID (a newer open for the same target replaces an unconsumed
/// one). `requestOpen` asks the host to open the target's pane. Mirrors the
/// AgentContext/Action hub shape (shared, `@MainActor`).
@MainActor
public final class PluginLaunchHub {
    private var pending: [String: String] = [:]
    private var openHandler: ((String) -> Void)?
    private var availabilityProvider: ((String) -> Availability)?
    private var openStateProvider: ((String) -> Bool)?

    /// Whether a target app can be opened right now.
    public enum Availability: Equatable, Sendable {
        case available
        /// Registered but switched off by the user.
        case disabled
        /// No app with that id — not installed, or failed to load.
        case unknown
    }

    public init() {}

    /// Wired once in bootstrap to open a pane via the WorkspaceManager.
    public func setOpenHandler(_ handler: @escaping (String) -> Void) { openHandler = handler }

    /// Wired once in bootstrap; lets a launch report *why* it didn't happen
    /// instead of silently doing nothing. Absent (tests, early bootstrap) means
    /// "assume available", preserving the pre-generation-8 behaviour exactly.
    public func setAvailabilityProvider(_ provider: @escaping (String) -> Availability) {
        availabilityProvider = provider
    }

    public func availability(of appID: String) -> Availability {
        availabilityProvider?(appID) ?? .available
    }

    /// Wired once in bootstrap, alongside the open handler. The counterpart to
    /// `requestOpen`: it answers whether the target is ALREADY open, so a
    /// caller that only needs a live shell can skip the launch entirely.
    /// Installed late (the host state it reads doesn't exist when this hub is
    /// constructed), which is why it's a provider rather than a stored flag.
    /// Absent means "assume closed" — the safe answer, since the worst outcome
    /// is a redundant open request.
    public func setOpenStateProvider(_ provider: @escaping (String) -> Bool) {
        openStateProvider = provider
    }

    public func isOpen(_ appID: String) -> Bool { openStateProvider?(appID) ?? false }

    public func enqueue(target appID: String, payload: String?) { pending[appID] = payload }

    public func requestOpen(_ appID: String) { openHandler?(appID) }

    /// Reads the pending payload WITHOUT consuming it.
    ///
    /// The open handler needs to know what a launch is asking for — which mode
    /// to open the pane in — before the target app exists to consume it.
    /// Consuming here would take the payload the app is about to read.
    public func peekPending(for appID: String) -> String? { pending[appID] }

    public func takePending(for appID: String) -> String? {
        defer { pending[appID] = nil }
        return pending[appID]
    }
}
