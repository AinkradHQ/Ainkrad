import Foundation
import AinkradSignal
import AinkradAppKit

/// A per-app emitter's view onto the host's feed.
///
/// Deliberately a protocol the host implements rather than a direct
/// `SignalCenter` reference: `AinkradHostRuntime` is a static library shared
/// with the dev host, and `SignalCenter` lives in the app target.
@MainActor
public protocol SignalEmitting: AnyObject {
    func record(_ appID: String, kind: String, severity: SignalSeverity, title: String,
                body: String?, importance: SignalImportance,
                deepLink: SignalDeepLink?, actions: [SignalAction], dedupeKey: String?)
    func events(forAppID appID: String, limit: Int) -> [SignalEvent]
}

/// Shared back end for every app's emitter. One per host, exactly like
/// `AgentContextRegistryHub` and `AgentActionRegistryHub`.
@MainActor
public final class SignalEmitterHub {
    private weak var sink: (any SignalEmitting)?
    private var handlers: [HandlerKey: Handler] = [:]

    private struct HandlerKey: Hashable {
        let appID: String
        let actionID: String
    }

    /// Holds the closure plus its token. The host registers once and never
    /// tears down, so a handler whose source is gone must degrade to a no-op
    /// rather than resurrect a dead app — the same contract as
    /// `AgentActionProvider`.
    private struct Handler {
        let token: AgentActionToken
        let run: @MainActor () async -> Void
    }

    public init(sink: (any SignalEmitting)? = nil) {
        self.sink = sink
    }

    /// Attached after construction: the feed is built later in bootstrap than
    /// the hub, which the plugin host services need early.
    public func attach(sink: any SignalEmitting) { self.sink = sink }

    func record(_ appID: String, kind: String, severity: SignalSeverity, title: String,
                body: String?, importance: SignalImportance,
                deepLink: SignalDeepLink?, actions: [SignalAction], dedupeKey: String?) {
        sink?.record(appID, kind: kind, severity: severity, title: title, body: body,
                     importance: importance, deepLink: deepLink,
                     actions: actions, dedupeKey: dedupeKey)
    }

    func events(forAppID appID: String, limit: Int) -> [SignalEvent] {
        sink?.events(forAppID: appID, limit: limit) ?? []
    }

    func register(actionID: String, appID: String,
                  run: @escaping @MainActor () async -> Void) -> AgentActionToken {
        let token = AgentActionToken()
        handlers[HandlerKey(appID: appID, actionID: actionID)] = Handler(token: token, run: run)
        return token
    }

    func remove(_ token: AgentActionToken) {
        handlers = handlers.filter { $0.value.token != token }
    }

    /// Invoked by the host when the user taps an action on a feed row. Scoped by
    /// `appID`, so one app's action id cannot shadow another's.
    public func invoke(actionID: String, appID: String) async {
        guard let handler = handlers[HandlerKey(appID: appID, actionID: actionID)] else { return }
        await handler.run()
    }
}

/// One app's view of the feed. Bound to `appID` at construction, which is the
/// entire forgery defence: there is no code path by which this type can emit as
/// anyone else, because `PluginSignalEmitter` has no `source` parameter to pass.
@MainActor
public final class HostSignalEmitter: PluginSignalEmitter {
    private let appID: String
    private let hub: SignalEmitterHub

    public init(appID: String, hub: SignalEmitterHub) {
        self.appID = appID
        self.hub = hub
    }

    public func emit(kind: String, severity: SignalSeverity, title: String, body: String?,
                     importance: SignalImportance, deepLink: SignalDeepLink?,
                     actions: [SignalAction], dedupeKey: String?) {
        hub.record(appID, kind: kind, severity: severity, title: title, body: body,
                   importance: importance, deepLink: deepLink,
                   actions: actions, dedupeKey: dedupeKey)
    }

    public func own(limit: Int) -> [SignalEvent] { hub.events(forAppID: appID, limit: limit) }

    public func handleAction(_ actionID: String,
                             _ handler: @escaping @MainActor () async -> Void) -> AgentActionToken {
        hub.register(actionID: actionID, appID: appID, run: handler)
    }

    public func removeActionHandler(_ token: AgentActionToken) { hub.remove(token) }
}
