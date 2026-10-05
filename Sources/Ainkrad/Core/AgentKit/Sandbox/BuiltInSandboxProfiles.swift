import Foundation

/// The immutable, shipped profiles. `workspace-write` is the default for every
/// non-main trust tier; `host-trusted` is used only for the main session.
enum BuiltInSandboxProfiles {
    static let mainID = "host-trusted"
    static let defaultNonMainID = "workspace-write"

    // NOTE: allowHostOverride stays FALSE here. The main-interactive tier gets
    // this profile without consulting the flag (the router's escalation check
    // only applies to non-main tiers); if it were true, any Agent policy naming
    // "host-trusted" would silently escalate a subagent/background run to host,
    // defeating the guard (and Task 9's nonMainCannotSilentlyEscalateToHost test).
    static let hostTrusted = SandboxProfile(
        id: mainID, name: "Host (trusted)", backend: .host,
        fsPolicy: FilesystemPolicy(readablePaths: ["/"], writablePaths: ["/"]),
        networkPolicy: .on,
        resourceLimits: ResourceLimits(timeoutSeconds: 30),  // matches today's RunTerminalTool default
        toolAllowList: [])

    static let readOnly = SandboxProfile(
        id: "read-only", name: "Read-only", backend: .seatbelt,
        fsPolicy: FilesystemPolicy(readablePaths: ["<workspace>"], writablePaths: []),
        networkPolicy: .off,
        resourceLimits: ResourceLimits(timeoutSeconds: 30),
        toolAllowList: [])

    static let workspaceWrite = SandboxProfile(
        id: defaultNonMainID, name: "Workspace write", backend: .seatbelt,
        fsPolicy: FilesystemPolicy(readablePaths: ["<workspace>"], writablePaths: ["<workspace>"]),
        networkPolicy: .off,
        resourceLimits: ResourceLimits(timeoutSeconds: 60),
        toolAllowList: [])

    static let networkedBuild = SandboxProfile(
        id: "networked-build", name: "Networked build", backend: .seatbelt,
        fsPolicy: FilesystemPolicy(readablePaths: ["<workspace>"], writablePaths: ["<workspace>"]),
        networkPolicy: .on,
        resourceLimits: ResourceLimits(timeoutSeconds: 300),
        toolAllowList: [])

    static let all: [SandboxProfile] = [hostTrusted, readOnly, workspaceWrite, networkedBuild]
    static var reservedIDs: Set<String> { Set(all.map { $0.id }) }
}
