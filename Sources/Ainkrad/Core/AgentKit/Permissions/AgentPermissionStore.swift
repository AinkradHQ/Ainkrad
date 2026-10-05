import AinkradHostRuntime
import Foundation
import Observation

struct AgentPermissionDocument: PersistableDocument {
    static let documentID = "agent-permissions"
    static let currentSchemaVersion = 2

    /// v1 → v2: the 2026-08-02 app rename. Rewrites allowlisted tool names so a
    /// user's approvals survive. Failing to migrate would fail SAFE (the tool
    /// re-prompts), unlike the hook migration in `ToolHooksDocument` — but a
    /// silently emptied allowlist is still a regression the user has to
    /// rediscover one approval at a time.
    static let migrators: [DocumentMigrator] = [
        DocumentMigrator(from: 1) { payload in
            guard case .object(var root) = payload,
                case .array(let list)? = root["allowlist"]
            else { return payload }
            root["allowlist"] = .array(
                list.map { entry in
                    guard case .string(let name) = entry else { return entry }
                    return .string(AppIDRenames.renamedToolName(name))
                })
            return .object(root)
        }
    ]

    var defaultMode: AgentPermissionMode = .ask
    var allowlist: [String] = []
    var perWorkspace: [String: AgentPermissionMode] = [:]
    /// Global (not per-workspace) toggle: when true, `.read` tools require approval in
    /// `Ask`/`Auto-approve` modes too (unless explicitly allowlisted).
    var gateReads: Bool = true

    init(
        defaultMode: AgentPermissionMode = .ask,
        allowlist: [String] = [],
        perWorkspace: [String: AgentPermissionMode] = [:],
        gateReads: Bool = true
    ) {
        self.defaultMode = defaultMode
        self.allowlist = allowlist
        self.perWorkspace = perWorkspace
        self.gateReads = gateReads
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultMode = try c.decodeIfPresent(AgentPermissionMode.self, forKey: .defaultMode) ?? .ask
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? []
        perWorkspace = try c.decodeIfPresent([String: AgentPermissionMode].self, forKey: .perWorkspace) ?? [:]
        gateReads = try c.decodeIfPresent(Bool.self, forKey: .gateReads) ?? true
    }
}

/// Owns the per-workspace permission mode + the auto-approve allowlist.
/// The active workspace id is read lazily via the injected closure so the store
/// stays decoupled from `WorkspaceManager` (and trivially testable).
@MainActor
@Observable
final class AgentPermissionStore {
    private var document: AgentPermissionDocument
    private let persistence: PersistenceStore
    private let currentWorkspaceID: @MainActor () -> UUID

    init(persistence: PersistenceStore, currentWorkspaceID: @escaping @MainActor () -> UUID) {
        self.persistence = persistence
        self.currentWorkspaceID = currentWorkspaceID
        self.document = persistence.load(AgentPermissionDocument.self) ?? AgentPermissionDocument()
    }

    var mode: AgentPermissionMode {
        document.perWorkspace[currentWorkspaceID().uuidString] ?? document.defaultMode
    }

    var allowlist: Set<String> { Set(document.allowlist) }

    var gateReads: Bool { document.gateReads }

    func setMode(_ mode: AgentPermissionMode) {
        document.perWorkspace[currentWorkspaceID().uuidString] = mode
        persistence.save(document)
    }

    /// Advance the current workspace's mode: ask -> autoApprove -> fullAuto -> ask.
    func cycle() {
        let next: AgentPermissionMode
        switch mode {
        case .ask: next = .autoApprove
        case .autoApprove: next = .fullAuto
        case .fullAuto: next = .ask
        }
        setMode(next)
    }

    func setGateReads(_ value: Bool) {
        document.gateReads = value
        persistence.save(document)
    }

    /// Append `toolName` to the persisted allowlist (no-op if already present),
    /// so a future call to that tool auto-approves in `Ask`/`Auto-approve`.
    func addToAllowlist(_ toolName: String) {
        guard !document.allowlist.contains(toolName) else { return }
        document.allowlist.append(toolName)
        persistence.save(document)
    }

    /// Remove `toolName` from the persisted allowlist (no-op if absent).
    func removeFromAllowlist(_ toolName: String) {
        guard let index = document.allowlist.firstIndex(of: toolName) else { return }
        document.allowlist.remove(at: index)
        persistence.save(document)
    }

    /// Empty the persisted allowlist (all "Allow always" grants revoked).
    func clearAllowlist() {
        guard !document.allowlist.isEmpty else { return }
        document.allowlist.removeAll()
        persistence.save(document)
    }
}
