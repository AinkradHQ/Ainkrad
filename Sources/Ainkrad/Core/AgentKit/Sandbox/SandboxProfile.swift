import Foundation

/// Which execution backend a profile targets.
enum SandboxBackendKind: String, Codable, Equatable, Sendable, CaseIterable {
    case host, seatbelt, docker, ssh, cloud
}

/// Network egress policy for a sandboxed run. Fail-closed default is `.off`.
enum NetworkPolicy: Codable, Equatable, Sendable {
    case off
    case allowList([String])  // permitted hostnames/domains
    case on

    // Explicit keyed coding so payloads are stable/human-editable.
    private enum CodingKeys: String, CodingKey { case off, allowList, on }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.allowList) {
            self = .allowList(try c.decode([String].self, forKey: .allowList))
        } else if c.contains(.on) {
            self = .on
        } else {
            self = .off
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .off: try c.encode([String: String](), forKey: .off)
        case .on: try c.encode([String: String](), forKey: .on)
        case .allowList(let hosts): try c.encode(hosts, forKey: .allowList)
        }
    }
}

/// Filesystem access policy. DENY by default: an empty policy (no paths listed)
/// grants no read or write access anywhere.
struct FilesystemPolicy: Codable, Equatable, Sendable {
    var readablePaths: [String]
    var writablePaths: [String]
}

/// Resource caps applied to a sandboxed run.
struct ResourceLimits: Codable, Equatable, Sendable {
    var cpuCount: Int? = nil
    var memoryMB: Int? = nil
    var timeoutSeconds: Int
}

/// A named, persisted isolation policy. `toolAllowList` empty means "defer to the
/// other permission layers" (no extra sandbox-level tool restriction).
struct SandboxProfile: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var backend: SandboxBackendKind
    var fsPolicy: FilesystemPolicy
    var networkPolicy: NetworkPolicy
    var resourceLimits: ResourceLimits
    var toolAllowList: Set<String>
    /// Explicit opt-in that lets a NON-main trust tier resolve to `.host`.
    /// Defaults false — fail-closed, no silent escalation.
    var allowHostOverride: Bool

    init(
        id: String, name: String, backend: SandboxBackendKind,
        fsPolicy: FilesystemPolicy, networkPolicy: NetworkPolicy,
        resourceLimits: ResourceLimits, toolAllowList: Set<String>,
        allowHostOverride: Bool = false
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.fsPolicy = fsPolicy
        self.networkPolicy = networkPolicy
        self.resourceLimits = resourceLimits
        self.toolAllowList = toolAllowList
        self.allowHostOverride = allowHostOverride
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, backend, fsPolicy, networkPolicy, resourceLimits, toolAllowList, allowHostOverride
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        backend = try c.decode(SandboxBackendKind.self, forKey: .backend)
        fsPolicy = try c.decode(FilesystemPolicy.self, forKey: .fsPolicy)
        networkPolicy = try c.decode(NetworkPolicy.self, forKey: .networkPolicy)
        resourceLimits = try c.decode(ResourceLimits.self, forKey: .resourceLimits)
        toolAllowList = try c.decodeIfPresent(Set<String>.self, forKey: .toolAllowList) ?? []
        allowHostOverride = try c.decodeIfPresent(Bool.self, forKey: .allowHostOverride) ?? false
    }

    /// A coarse, defense-in-depth permissiveness check used by
    /// `ExecutionRouter`'s background-tier narrowing ceiling. Profiles don't
    /// have a total ordering in general (arbitrary custom profiles could
    /// differ in incomparable ways), so this is deliberately conservative:
    /// it only says "no more permissive" when EVERY dimension we can compare
    /// (network openness, and readable/writable filesystem scope) is no
    /// broader than `baseline`. Any dimension we can't clearly compare (or
    /// that is broader) fails the check, which is the fail-closed direction.
    func isNoMorePermissive(than baseline: SandboxProfile) -> Bool {
        guard Self.networkRank(networkPolicy) <= Self.networkRank(baseline.networkPolicy) else { return false }
        guard Set(fsPolicy.writablePaths).isSubset(of: Set(baseline.fsPolicy.writablePaths)) else { return false }
        guard Set(fsPolicy.readablePaths).isSubset(of: Set(baseline.fsPolicy.readablePaths)) else { return false }
        return true
    }

    /// Openness ordering for `NetworkPolicy`: fully blocked < an explicit
    /// allow-list < unrestricted.
    private static func networkRank(_ policy: NetworkPolicy) -> Int {
        switch policy {
        case .off: return 0
        case .allowList: return 1
        case .on: return 2
        }
    }
}
