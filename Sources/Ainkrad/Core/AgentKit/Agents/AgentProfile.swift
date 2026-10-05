// Sources/Ainkrad/Core/AgentKit/Agents/AgentProfile.swift
import Foundation

enum ModelTierCode: String, Codable, Sendable, CaseIterable {
    case local, free, cheapPaid, premium
}

struct AgentRouting: Codable, Equatable, Sendable {
    var routerEnabled: Bool
    var preferredModels: [String]
    var allowedModels: [String]  // empty = unrestricted
    var maxTier: ModelTierCode?  // nil = no ceiling

    init(
        routerEnabled: Bool = true, preferredModels: [String] = [],
        allowedModels: [String] = [], maxTier: ModelTierCode? = nil
    ) {
        self.routerEnabled = routerEnabled
        self.preferredModels = preferredModels
        self.allowedModels = allowedModels
        self.maxTier = maxTier
    }
}

struct AgentProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var instructions: String
    var toolPolicy: AgentToolPolicy
    var defaultModel: String?
    /// nil = inherit the workspace permission mode; non-nil composes
    /// most-restrictive-wins with it (Task 4 `effectiveMode()`).
    var permissionPosture: AgentPermissionMode?
    var routing: AgentRouting
    let builtin: Bool
    /// SF Symbol name. Defaults to "sparkles" for forward-compatible decode
    /// of agents persisted before this field existed.
    var icon: String

    init(
        id: UUID = UUID(), name: String, instructions: String,
        toolPolicy: AgentToolPolicy, defaultModel: String? = nil,
        permissionPosture: AgentPermissionMode? = nil,
        routing: AgentRouting = AgentRouting(), builtin: Bool = false,
        icon: String = "sparkles"
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.toolPolicy = toolPolicy
        self.defaultModel = defaultModel
        self.permissionPosture = permissionPosture
        self.routing = routing
        self.builtin = builtin
        self.icon = icon
    }

    static func custom(name: String, instructions: String) -> AgentProfile {
        AgentProfile(name: name, instructions: instructions, toolPolicy: .all)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, instructions, toolPolicy, defaultModel, permissionPosture, routing, builtin, icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        instructions = try container.decode(String.self, forKey: .instructions)
        toolPolicy = try container.decode(AgentToolPolicy.self, forKey: .toolPolicy)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
        permissionPosture = try container.decodeIfPresent(AgentPermissionMode.self, forKey: .permissionPosture)
        routing = try container.decodeIfPresent(AgentRouting.self, forKey: .routing) ?? AgentRouting()
        builtin = try container.decodeIfPresent(Bool.self, forKey: .builtin) ?? false
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(toolPolicy, forKey: .toolPolicy)
        try container.encodeIfPresent(defaultModel, forKey: .defaultModel)
        try container.encodeIfPresent(permissionPosture, forKey: .permissionPosture)
        try container.encode(routing, forKey: .routing)
        try container.encode(builtin, forKey: .builtin)
        try container.encode(icon, forKey: .icon)
    }
}
