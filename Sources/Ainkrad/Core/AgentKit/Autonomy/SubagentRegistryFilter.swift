// Sources/Ainkrad/Core/AgentKit/Autonomy/SubagentRegistryFilter.swift
import Foundation

/// Narrows a subagent's tool surface. This is the isolation seam between the
/// parent's full tool registry and what a spawned subagent may actually call:
/// a subagent can never exceed its granted surface even though orchestration
/// happens in-process (`AgentToolRegistry` exposes no enumeration, so we filter
/// the source array and re-construct rather than mutate a shared registry).
///
/// NARROWS-ONLY invariant: the output is always a subset of `all`. Neither
/// `allow` naming an unknown tool nor `policy` can introduce a tool that
/// wasn't already present in the source array — they can only remove tools.
enum SubagentRegistryFilter {
    @MainActor
    static func tools(
        from all: [any AgentTool], allow: [String],
        policy: AgentToolPolicy?
    ) -> [any AgentTool] {
        all.filter { tool in
            let allowed = allow.isEmpty || allow.contains(tool.name)
            let byPolicy = policy?.allows(toolName: tool.name, permission: tool.permission) ?? true
            return allowed && byPolicy
        }
    }
}
