import AinkradHostRuntime
import Foundation
import Observation

struct AgentConfigDocument: PersistableDocument {
    static let documentID = "agent-config"

    var activeConnectionID: UUID?
    var model: String = "claude-opus-4-8"
    var effort: String = "xhigh"

    init(activeConnectionID: UUID? = nil, model: String = "claude-opus-4-8", effort: String = "xhigh") {
        self.activeConnectionID = activeConnectionID
        self.model = model
        self.effort = effort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeConnectionID = try c.decodeIfPresent(UUID.self, forKey: .activeConnectionID)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "claude-opus-4-8"
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? "xhigh"
        // Legacy `provider` field (if present) is ignored — the active
        // connection is resolved from the connection list at runtime.
    }

    enum CodingKeys: String, CodingKey { case activeConnectionID, model, effort }
}

@MainActor
@Observable
final class AgentConfigStore {
    private(set) var current: AgentModelConfig
    private(set) var activeConnectionID: UUID?
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(AgentConfigDocument.self) ?? AgentConfigDocument()
        self.activeConnectionID = document.activeConnectionID
        self.current = AgentModelConfig(model: document.model, effort: document.effort)
    }

    func setActiveConnectionID(_ id: UUID?) {
        activeConnectionID = id
        save()
    }
    func setModel(_ model: String) {
        current.model = model
        save()
    }
    func setEffort(_ effort: String) {
        current.effort = effort
        save()
    }

    private func save() {
        persistence.save(
            AgentConfigDocument(
                activeConnectionID: activeConnectionID, model: current.model, effort: current.effort))
    }
}

/// Per-session assistant runtime toggles: verbose/trace display flags, the `/think`
/// reasoning-effort level, a session-scoped model pin (`/model`, cleared on `/new`),
/// and the router's cost/quality policy. Distinct from `AgentConfigDocument` (the
/// standing default model/effort) — this is the ephemeral layer `resolveTurn()`
/// consults FIRST, before falling back to the Agent's default or the config.
struct SageRuntimeOptions: PersistableDocument {
    static let documentID = "assistant-runtime"
    var verbose = false
    var trace = false
    var thinkLevel = "medium"
    var pinnedModel: String? = nil
    var routerPolicy: RouterPolicy = .saveMoney

    init(
        verbose: Bool = false, trace: Bool = false, thinkLevel: String = "medium",
        pinnedModel: String? = nil, routerPolicy: RouterPolicy = .saveMoney
    ) {
        self.verbose = verbose
        self.trace = trace
        self.thinkLevel = thinkLevel
        self.pinnedModel = pinnedModel
        self.routerPolicy = routerPolicy
    }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults) so a
    // payload missing newer keys never throws. See RouterOutcomeDocument / UsageLedgerDocument.
    private enum CodingKeys: String, CodingKey { case verbose, trace, thinkLevel, pinnedModel, routerPolicy }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verbose = try c.decodeIfPresent(Bool.self, forKey: .verbose) ?? false
        trace = try c.decodeIfPresent(Bool.self, forKey: .trace) ?? false
        thinkLevel = try c.decodeIfPresent(String.self, forKey: .thinkLevel) ?? "medium"
        pinnedModel = try c.decodeIfPresent(String.self, forKey: .pinnedModel)
        routerPolicy = try c.decodeIfPresent(RouterPolicy.self, forKey: .routerPolicy) ?? .saveMoney
    }
}

@MainActor
@Observable
final class RuntimeOptionsStore {
    private(set) var options: SageRuntimeOptions
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.options = persistence.load(SageRuntimeOptions.self) ?? SageRuntimeOptions()
    }

    func setVerbose(_ v: Bool) {
        options.verbose = v
        save()
    }
    func setTrace(_ v: Bool) {
        options.trace = v
        save()
    }
    func setThinkLevel(_ v: String) {
        options.thinkLevel = v
        save()
    }
    func pinModel(_ id: String?) {
        options.pinnedModel = id
        save()
    }
    func setPolicy(_ p: RouterPolicy) {
        options.routerPolicy = p
        save()
    }

    /// `/new` / `/reset` clears only the session-scoped model pin — verbose/trace/
    /// thinkLevel/routerPolicy are standing preferences, not per-session state.
    func resetForNewSession() {
        options.pinnedModel = nil
        save()
    }

    private func save() { persistence.save(options) }
}
