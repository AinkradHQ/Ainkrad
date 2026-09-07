import Foundation
import AinkradSignal

/// What an emitter can express. Deliberately has **no `source` field**: the
/// only way to name a source is `SignalIngest.accept(_:from:)`, whose `from`
/// the host supplies. Forgery is therefore not expressible in the API rather
/// than merely rejected by it.
public struct SignalDraft: Sendable, Equatable {
    public var kind: String
    public var severity: SignalSeverity
    public var title: String
    public var body: String?
    public var importance: SignalImportance
    public var deepLink: SignalDeepLink?
    public var actions: [SignalAction]
    public var dedupeKey: String?

    public init(kind: String,
                severity: SignalSeverity,
                title: String,
                body: String? = nil,
                importance: SignalImportance = .normal,
                deepLink: SignalDeepLink? = nil,
                actions: [SignalAction] = [],
                dedupeKey: String? = nil) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.body = body
        self.importance = importance
        self.deepLink = deepLink
        self.actions = actions
        self.dedupeKey = dedupeKey
    }
}

public enum SignalRejection: Equatable, Sendable {
    case invalidKind(String)
    case emptyTitle
    case storeUnavailable
}

public enum SignalIngestOutcome: Equatable, Sendable {
    case accepted(SignalEvent)
    case coalesced(SignalEvent)
    case rejected(SignalRejection)
}

/// Validates, stamps and persists. Pure of UI and of delivery: what happens
/// *next* is `SignalCenter`'s business.
public struct SignalIngest {
    private let store: SignalStore
    private let clock: () -> Date

    public init(store: SignalStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    public func accept(_ draft: SignalDraft, from source: SignalSource) -> SignalIngestOutcome {
        guard SignalKind.isValid(draft.kind) else { return .rejected(.invalidKind(draft.kind)) }
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected(.emptyTitle)
        }
        let event = SignalEvent(
            timestamp: clock(),
            source: source,
            kind: draft.kind,
            severity: draft.severity,
            title: draft.title,
            body: draft.body,
            proposedImportance: draft.importance,
            deepLink: draft.deepLink,
            actions: draft.actions,
            dedupeKey: draft.dedupeKey
        ).normalized(source: source)

        do {
            switch try store.insert(event) {
            case .inserted: return .accepted(event)
            case .coalesced: return .coalesced(event)
            @unknown default:
                // AinkradSignal builds with library evolution, so its enums are
                // non-frozen to consumers. A future outcome we do not know about
                // still means the event reached the store, so report acceptance
                // rather than inventing a rejection the caller cannot act on.
                return .accepted(event)
            }
        } catch {
            return .rejected(.storeUnavailable)
        }
    }
}
