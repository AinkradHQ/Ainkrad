import Foundation

/// Where a skill came from. Assigned by the loader (never read from the file).
enum SkillSource: String, Codable, Equatable {
    case marketplace, local, proposed
}

/// A reusable procedure parsed from an agentskills.io `SKILL.md`.
struct Skill: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let body: String  // markdown instructions (below the front matter)
    let allowedTools: [String]  // optional tool allow-list (advisory in v1)
    let triggers: [String]  // optional trigger hints
    var source: SkillSource
}
