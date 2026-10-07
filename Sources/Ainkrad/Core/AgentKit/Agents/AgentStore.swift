import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Agents/AgentStore.swift
import Foundation
import Observation

struct AgentsDocument: PersistableDocument {
    static let documentID = "agents"
    var custom: [AgentProfile] = []
    var activeID: UUID? = nil

    init(custom: [AgentProfile] = [], activeID: UUID? = nil) {
        self.custom = custom
        self.activeID = activeID
    }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults).
    enum CodingKeys: String, CodingKey { case custom, activeID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        custom = try c.decodeIfPresent([AgentProfile].self, forKey: .custom) ?? []
        activeID = try c.decodeIfPresent(UUID.self, forKey: .activeID)
    }
}

@MainActor
@Observable
final class AgentStore {
    private(set) var agents: [AgentProfile] = []
    private var document: AgentsDocument
    private let persistence: PersistenceStore
    var persistenceForTesting: PersistenceStore { persistence }

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(AgentsDocument.self) ?? AgentsDocument()
        rebuild()
    }

    var active: AgentProfile {
        if let id = document.activeID, let match = agents.first(where: { $0.id == id }) {
            return match
        }
        return BuiltInAgents.build
    }

    func setActive(_ id: UUID) {
        guard agents.contains(where: { $0.id == id }) else { return }
        document.activeID = id
        save()
    }

    /// Advances the active agent to the next one in `agents` (wrapping around).
    /// Backs the composer's Tab-cycle affordance (M7 Slice 5a).
    func cycleActive() {
        guard !agents.isEmpty else { return }
        let i = agents.firstIndex { $0.id == active.id } ?? 0
        setActive(agents[(i + 1) % agents.count].id)
    }

    @discardableResult
    func add(_ profile: AgentProfile) -> AgentProfile {
        document.custom.append(profile)
        save()
        return profile
    }

    func update(_ profile: AgentProfile) {
        guard !profile.builtin, let i = document.custom.firstIndex(where: { $0.id == profile.id }) else { return }
        document.custom[i] = profile
        save()
    }

    func delete(_ id: UUID) {
        guard !BuiltInAgents.all.contains(where: { $0.id == id }) else { return }
        document.custom.removeAll { $0.id == id }
        if document.activeID == id { document.activeID = BuiltInAgents.buildID }
        save()
    }

    func clone(_ id: UUID) -> AgentProfile {
        let source = agents.first { $0.id == id } ?? BuiltInAgents.build
        let copy = AgentProfile(
            name: "\(source.name) Copy", instructions: source.instructions,
            toolPolicy: source.toolPolicy, defaultModel: source.defaultModel,
            permissionPosture: source.permissionPosture, routing: source.routing, builtin: false,
            icon: source.icon)
        return add(copy)
    }

    private func rebuild() { agents = BuiltInAgents.all + document.custom }
    private func save() {
        persistence.save(document)
        rebuild()
    }
}
