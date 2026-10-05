import AinkradAppKit
import AinkradHostRuntime
import Foundation
// Tests/AinkradTests/RunTerminalRemoteTests.swift
import Testing

@testable import Ainkrad

/// A fake remote target. Nothing in this file ever connects to it: the `.ssh`
/// backend under test runs `/usr/bin/false` in place of `ssh`.
private let fakeRemoteConnection = SSHConnectionInfo(
    host: "web.example.com", user: "deploy", port: 2222,
    identityPath: nil, remoteWorkingDir: nil)

/// The four refusals a user can actually hit. The first is the host's own
/// (Leyline absent); the other three are `LeylineConnectionBridge`'s, passed
/// through verbatim so the specific, actionable cause survives the trip.
private let resolverFailureReasons: [String] = [
    "No SSH connection provider is available — the Leyline app is not installed or did not "
        + "load. Install Leyline and add the connection there, then run this again.",
    "leyline.resolve_connection: no saved connection has that id.",
    "Connection \"Legacy box\" authenticates with a password, and background execution runs "
        + "ssh with BatchMode=yes ... Attach an SSH key to this connection in the Leyline app.",
    "Connection \"Staging box\" uses key \"Locked key\", which is passphrase-protected, and "
        + "background execution runs ssh with BatchMode=yes ... Attach a key with no passphrase "
        + "to this connection in the Leyline app.",
]

/// `run_terminal`'s `remote` argument: routing, always-approve, and the
/// unchanged-without-`remote` guarantee.
///
/// **No test here makes a real SSH connection or touches the Keychain.** The
/// only backend that ever spawns is `HostBackend` (for the local-path tests);
/// the `.ssh` backend is built with an injected resolver that either fails or
/// returns a fake connection whose `ssh` binary is `/usr/bin/false`.
@MainActor
@Suite("run_terminal — remote execution", .timeLimit(.minutes(1)))
struct RunTerminalRemoteTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    /// A router with a real `HostBackend` *and* an `.ssh` backend, so a test
    /// that asserts "the remote run did not run locally" is asserting something
    /// — the local path is genuinely wired and would have worked.
    private func router(resolver: SSHConnectionResolver?, sshPath: String = "/usr/bin/false")
        -> ExecutionRouter
    {
        var ssh = SSHBackend(resolveConnection: resolver)
        ssh.sshPath = sshPath
        return ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend(), .ssh: ssh])
    }

    // MARK: - Fail-closed

    /// The single most important property in this change: each of the four
    /// user-reachable failures blocks the run AND leaves no local trace. The
    /// marker file is the proof — the command would have created it had it
    /// leaked to the local shell.
    @Test(
        "Leyline absent, unknown id, password-only and passphrase-protected never run locally",
        arguments: resolverFailureReasons)
    func remoteFailuresNeverRunLocally(reason: String) async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("ain-remote-fail-closed-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: marker) }

        // Bound locally: the tool holds both `unowned`.
        let hub = AgentActionRegistryHub()
        let router = router(resolver: { _ in .failure(SSHConnectionResolutionFailure(reason)) })
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let result = try await tool.execute(
            obj([
                "command": .string("touch \(marker.path)"),
                "remote": .string("prod-web"),
            ]))

        #expect(result.isError)
        // Nothing ran here.
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        // And the user is told the SPECIFIC cause, not a generic failure.
        #expect(result.content.contains(reason))
        #expect(result.content.contains("not executed locally"))
    }

    /// The same command with NO `remote` really does run locally — so the test
    /// above is proving a difference, not an inert path.
    @Test("the control: the same command without remote does run locally")
    func controlLocalRunActuallyRuns() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("ain-remote-control-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: marker) }

        let hub = AgentActionRegistryHub()
        let router = router(resolver: { _ in .success(fakeRemoteConnection) })
        let tool = RunTerminalTool(actionHub: hub, router: router)
        _ = try await tool.execute(obj(["command": .string("touch \(marker.path)")]))
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    /// With no `.ssh` backend registered at all, a remote run is blocked by the
    /// router rather than quietly resolving to the local host backend.
    @Test("an unregistered ssh backend blocks the run, never falls back to host")
    func unregisteredSSHBackendBlocks() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("ain-remote-nobackend-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: marker) }

        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])  // no .ssh
        let hub = AgentActionRegistryHub()
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let result = try await tool.execute(
            obj([
                "command": .string("touch \(marker.path)"),
                "remote": .string("prod-web"),
            ]))
        #expect(result.isError)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: - Routing

    /// `remote` overrides the tier's backend, and the resolver is asked for the
    /// id the call named — per call, with no ambient "active remote".
    @Test("remote sends the run to the ssh backend regardless of tier")
    func remoteOverridesTier() async throws {
        for tier in [TrustTier.mainInteractive, .background, .subagent] {
            let asked = ResolverProbe()
            let hub = AgentActionRegistryHub()
            let router = router(resolver: { id in
                await asked.record(id)
                return .success(fakeRemoteConnection)
            })
            var tool = RunTerminalTool(actionHub: hub, router: router)
            tool.trustTier = tier
            // sshPath is /usr/bin/false, so the run "fails" — what matters is
            // that it went through SSHBackend at all.
            _ = try await tool.execute(
                obj([
                    "command": .string("uptime"), "remote": .string("prod-web"),
                ]))
            #expect(await asked.ids == ["prod-web"], "tier \(tier) did not route to ssh")
        }
    }

    @Test("the ssh run still gets a profile, so its timeout still bounds the run")
    func remoteStillGetsProfileLimits() async throws {
        let seen = ProfileProbe()
        var ssh = SSHBackend(resolveConnection: { _ in .success(fakeRemoteConnection) })
        ssh.sshPath = "/usr/bin/false"
        let recording = RecordingBackend(inner: ssh, probe: seen)
        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend(), .ssh: recording])
        let hub = AgentActionRegistryHub()
        var tool = RunTerminalTool(actionHub: hub, router: router)
        tool.timeout = 7  // the existing test seam overrides the profile timeout
        _ = try await tool.execute(
            obj([
                "command": .string("uptime"), "remote": .string("prod-web"),
            ]))
        #expect(await seen.timeoutSeconds == 7)
        #expect(await seen.remote == "prod-web")
    }

    // MARK: - Always approve

    /// Every remote command requires approval in EVERY mode — allowlisted and
    /// trusted included. `isIrreversible` is the only mechanism that always
    /// prompts, so `RunTerminalTool` sets it for any call carrying `remote`.
    @Test("a remote run requires approval in all three modes, allowlisted and trusted")
    func remoteAlwaysRequiresApproval() {
        let hub = AgentActionRegistryHub()
        let router = router(resolver: { _ in .success(fakeRemoteConnection) })
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let input = obj(["command": .string("uptime"), "remote": .string("prod-web")])
        #expect(tool.isIrreversible(input))

        for mode in AgentPermissionMode.allCases {
            for trusted in [false, true] {
                let decision = AgentPermissionPolicy.decide(
                    toolPermission: tool.permission,
                    toolName: tool.name,
                    mode: mode,
                    allowlist: ["run_terminal"],  // allowlisted
                    gateReads: false,
                    isIrreversible: tool.isIrreversible(input),
                    isTrusted: trusted)
                #expect(
                    decision == .requireApproval,
                    "mode \(mode), trusted \(trusted) did not require approval")
            }
        }
    }

    /// Even a completely benign command is outward-facing when it is remote.
    @Test("a harmless remote command still requires approval")
    func harmlessRemoteStillPrompts() {
        let hub = AgentActionRegistryHub()
        let router = router(resolver: nil)
        let tool = RunTerminalTool(actionHub: hub, router: router)
        #expect(
            tool.isIrreversible(
                obj([
                    "command": .string("echo hi"),
                    "remote": .string("prod-web"),
                ])))
        // A blank remote is not a remote — it must not silently make every
        // local run always-approve either.
        #expect(
            !tool.isIrreversible(
                obj([
                    "command": .string("echo hi"),
                    "remote": .string("   "),
                ])))
    }

    @Test("the approval card names the connection and shows the command")
    func approvalPreviewNamesHostAndCommand() {
        let hub = AgentActionRegistryHub()
        let router = router(resolver: nil)
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let preview = tool.approvalPreview(
            obj([
                "command": .string("systemctl restart nginx"), "remote": .string("prod-web"),
            ]))
        #expect(preview.title == "Remote: prod-web")
        #expect(preview.summary == "systemctl restart nginx")
    }

    /// The property this whole label-addressing change exists to produce.
    ///
    /// Leyline connection ids are UUIDs, and `approvalPreview` is synchronous,
    /// so it cannot look a label up — it can only print what the model passed.
    /// A card reading `Remote: 9F3A1C2E-…` above `systemctl restart nginx`
    /// gives the user nothing to catch a wrong-host mistake with, which is the
    /// only reason the gate exists. Leyline now accepts a label, and the schema
    /// below is the single lever that makes the model send one.
    @Test("a supplied label reaches the approval card verbatim, and the schema asks for one")
    func approvalCardReadsTheLabel() throws {
        let hub = AgentActionRegistryHub()
        let tool = RunTerminalTool(actionHub: hub, router: router(resolver: nil))

        let byLabel = tool.approvalPreview(
            obj([
                "command": .string("systemctl restart nginx"), "remote": .string("prod-web"),
            ]))
        #expect(byLabel.title == "Remote: prod-web")
        #expect(!byLabel.title.contains("-4B7D-"))

        // A UUID still works — it must, for the ambiguous-label case — but it
        // is what the card is NOT supposed to read, so the steer lives in the
        // schema description rather than in a rejection here.
        let uuid = "9F3A1C2E-4B7D-4E19-9A6B-0C1D2E3F4A5B"
        #expect(
            tool.approvalPreview(
                obj([
                    "command": .string("uptime"),
                    "remote": .string(uuid),
                ])
            ).title == "Remote: \(uuid)")

        let described = try #require(
            tool.parametersSchema["properties"]?["remote"]?["description"]?.stringValue)
        #expect(described.contains("label"))
        #expect(described.contains("PREFER THE LABEL"))
        #expect(described.contains("approval card"))
    }

    // MARK: - No `remote` ⇒ unchanged

    @Test("without remote, the tool behaves exactly as before")
    func absentRemoteIsUnchanged() async throws {
        let hub = AgentActionRegistryHub()
        let router = router(resolver: { _ in .success(fakeRemoteConnection) })
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let local = obj(["command": .string("echo hello-ainkrad")])

        // Runs locally, captures output, reports the exit code.
        let result = try await tool.execute(local)
        #expect(!result.isError)
        #expect(result.content.contains("hello-ainkrad"))
        #expect(result.content.contains("[exit 0]"))

        // Not always-approve, and the old approval card is untouched.
        #expect(!tool.isIrreversible(local))
        #expect(tool.approvalPreview(local).title == "Run terminal")
        #expect(tool.approvalPreview(local).summary == "echo hello-ainkrad")

        // The destructive heuristics still decide local runs on their own.
        #expect(tool.isIrreversible(obj(["command": .string("rm -rf /tmp/x")])))

        // And `decide` still auto-approves a local run in full-auto.
        #expect(
            AgentPermissionPolicy.decide(
                toolPermission: tool.permission, toolName: tool.name, mode: .fullAuto,
                allowlist: [], gateReads: false,
                isIrreversible: tool.isIrreversible(local)) == .autoApprove)
    }

    @Test("the schema advertises remote as an optional saved-connection id")
    func schemaDescribesRemote() throws {
        let hub = AgentActionRegistryHub()
        let router = router(resolver: nil)
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let properties = try #require(tool.parametersSchema["properties"])
        let remote = try #require(properties["remote"])
        #expect(remote["type"]?.stringValue == "string")
        let description = try #require(remote["description"]?.stringValue)
        #expect(description.contains("Leyline"))
        #expect(description.localizedCaseInsensitiveContains("approval"))
        // Still optional: only `command` is required.
        guard case .array(let required) = try #require(tool.parametersSchema["required"]) else {
            Issue.record("required should be an array")
            return
        }
        #expect(required.compactMap(\.stringValue) == ["command"])
    }
}

// MARK: - Probes

private actor ResolverProbe {
    private(set) var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}

private actor ProfileProbe {
    private(set) var timeoutSeconds: Int?
    private(set) var remote: String?
    func record(_ request: ExecutionRequest) {
        timeoutSeconds = request.profile.resourceLimits.timeoutSeconds
        remote = request.remote
    }
}

/// Wraps a backend to capture the `ExecutionRequest` it was handed.
private struct RecordingBackend: ExecutionBackend {
    let inner: any ExecutionBackend
    let probe: ProfileProbe
    var kind: SandboxBackendKind { inner.kind }
    func isAvailable() async -> Bool { await inner.isAvailable() }
    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        await probe.record(request)
        return try await inner.run(request)
    }
}
