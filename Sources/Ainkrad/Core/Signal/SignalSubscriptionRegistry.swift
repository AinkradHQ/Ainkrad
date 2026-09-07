import Foundation
import AinkradAppKit
import AinkradSignal

/// Persists what each app declared and what the user approved.
///
/// Separate from the registry so the registry stays testable without touching
/// disk, and so a corrupt file degrades to "nothing is approved" — the safe
/// direction — rather than to a crash at launch.
final class SignalSubscriptionStore {
    private let url: URL

    init(url: URL) { self.url = url }

    /// Approved patterns per appID, as their canonical string form.
    func load() -> [String: Set<String>] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return raw.mapValues(Set.init)
    }

    func save(_ approved: [String: Set<String>]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(approved.mapValues { Array($0).sorted() })
        else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.registry.error("Failed to write \(data.count, privacy: .public) bytes to \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Routes events to apps that declared an interest and whose user approved it.
///
/// ## Approval is for a LIST, and the list can change under it
///
/// An app declares subscriptions in its manifest; the user approves. Then the
/// app updates. The question this type exists to answer correctly is what
/// happens to that approval when the declared list changes:
///
/// - **Widened** → approval is suspended and nothing is delivered until the
///   user answers again. Not just the new entries: consent was for a list, and
///   the list is different. Delivering the old subset while the question is
///   outstanding would make widening a way to stay half-live without asking.
/// - **Narrowed** → still approved. Strictly less access than the user already
///   allowed, and re-asking trains people to approve without reading.
/// - **Reordered** → still approved. A hash of the list would re-prompt on a
///   cosmetic manifest edit, and a prompt the user cannot explain is one they
///   learn to click through.
///
/// That is why approval stores the approved SET and `isApproved` is a subset
/// test, rather than the pattern-list hash the plan suggested.
@MainActor
final class SignalSubscriptionRegistry {
    private let store: SignalSubscriptionStore?

    private var declared: [String: [SignalSubscription]] = [:]
    /// Canonical pattern strings the user approved, per appID.
    private var approved: [String: Set<String>] = [:]

    /// Weak, so an app that was unloaded cannot be kept alive by the feed —
    /// and cannot be resurrected by an event arriving after its teardown. The
    /// same doctrine as `AgentActionToken`: register once, hold weakly, no-op
    /// once the source is gone.
    private final class WeakObserver {
        weak var observer: (any PluginSignalObserver)?
        init(_ observer: any PluginSignalObserver) { self.observer = observer }
    }
    private var observers: [String: WeakObserver] = [:]

    init(store: SignalSubscriptionStore? = nil) {
        self.store = store
        self.approved = store?.load() ?? [:]
    }

    // MARK: - Declarations and approval

    func setDeclared(_ subscriptions: [SignalSubscription], for appID: String) {
        declared[appID] = subscriptions
    }

    func declared(for appID: String) -> [SignalSubscription] { declared[appID] ?? [] }

    /// True when everything currently declared is inside what the user
    /// approved. An app that declares nothing is trivially approved and
    /// receives nothing, which is the correct answer to a question nobody
    /// asked.
    func isApproved(appID: String) -> Bool {
        let wanted = Set(declared(for: appID).map(Self.canonical))
        guard !wanted.isEmpty else { return true }
        guard let allowed = approved[appID] else { return false }
        return wanted.isSubset(of: allowed)
    }

    /// Records approval for exactly what is declared right now.
    func approve(appID: String) {
        approved[appID] = Set(declared(for: appID).map(Self.canonical))
        store?.save(approved)
    }

    /// Withdraws approval. Takes effect on the next `fanOut` with no relaunch,
    /// because `isApproved` is consulted per event rather than cached into the
    /// observer registration.
    func revoke(appID: String) {
        approved[appID] = nil
        store?.save(approved)
    }

    /// Whether this app has ever had an approval recorded, regardless of
    /// whether it still covers what the app now declares.
    ///
    /// Distinguishes "asking for the first time" from "asking again after
    /// widening", which is the difference between a prompt that introduces
    /// itself and one that explains why it is back.
    func hasEverBeenApproved(appID: String) -> Bool { approved[appID] != nil }

    /// Apps that declared something the user has not approved — what the
    /// approval UI asks about.
    func appsAwaitingApproval() -> [String] {
        declared.keys.filter { !declared(for: $0).isEmpty && !isApproved(appID: $0) }.sorted()
    }

    // MARK: - Observers

    func register(observer: any PluginSignalObserver, appID: String) {
        observers[appID] = WeakObserver(observer)
    }

    func unregister(appID: String) { observers[appID] = nil }

    var liveObserverCountForTesting: Int {
        observers.values.filter { $0.observer != nil }.count
    }

    /// Delivers one event to every approved, matching, still-live observer.
    ///
    /// Called by `SignalCenter` after its own delivery, so a subscriber can
    /// never see an event before the user's own surfaces do.
    func fanOut(_ event: SignalEvent) {
        // Drop dead boxes as we pass, so an app that loaded and unloaded
        // repeatedly does not leave a growing table of nils behind.
        for (appID, box) in observers {
            guard let observer = box.observer else {
                observers[appID] = nil
                continue
            }
            // An app never receives its own events here. It already sees them
            // through `own(limit:)`, and delivering them back would invite an
            // emit-inside-signalDidArrive loop that this type does not break.
            if case .app(let sourceAppID) = event.source, sourceAppID == appID { continue }
            guard isApproved(appID: appID) else { continue }
            guard declared(for: appID).contains(where: { $0.matches(event) }) else { continue }
            observer.signalDidArrive(event)
        }
    }

    /// The stable string form of a subscription, used as the approval unit.
    /// Rebuilt from the parsed value rather than kept from the manifest text,
    /// so two spellings of the same subscription cannot count as different
    /// consents.
    private static func canonical(_ subscription: SignalSubscription) -> String {
        let source: String
        switch subscription.source {
        case .host: source = "host"
        case .sage: source = "sage"
        case .app(let appID): source = "app:\(appID)"
        @unknown default: source = "unknown"
        }
        let kind = subscription.isWildcard
            ? (subscription.kindPattern.isEmpty ? "*" : "\(subscription.kindPattern).*")
            : subscription.kindPattern
        return "\(source)/\(kind)"
    }
}
