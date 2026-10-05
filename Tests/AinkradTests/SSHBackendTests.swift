import AinkradAppKit
import AinkradHostRuntime
// Tests/AinkradTests/SSHBackendTests.swift
import Foundation
import Testing

@testable import Ainkrad

/// A connection that could be spawned against, if anything ever got that far.
/// No test here makes a real SSH connection: the one test that reaches a spawn
/// points `sshPath` at `/usr/bin/false`.
private let fakeConnection = SSHConnectionInfo(
    host: "h", user: "u", port: nil,
    identityPath: nil, remoteWorkingDir: nil)

/// A resolver that always fails with `reason` — stands in for Leyline saying
/// "unknown id" / "password-only" / "passphrase-protected" without any plugin,
/// any Keychain, or any network.
private func failing(_ reason: String) -> SSHConnectionResolver {
    { _ in .failure(SSHConnectionResolutionFailure(reason)) }
}

private func succeeding() -> SSHConnectionResolver { { _ in .success(fakeConnection) } }

/// Runs `command` through `backend` and asserts it threw AND left no local
/// trace. The marker is the actual proof of fail-closed: if the command had
/// leaked to a local shell it would exist.
@discardableResult
private func expectBlockedWithNoLocalExecution(
    _ backend: SSHBackend, remote: String?, sourceLocation: SourceLocation = #_sourceLocation
) async -> String? {
    let marker = FileManager.default.temporaryDirectory
        .appendingPathComponent("ain-ssh-fail-closed-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: marker) }

    var message: String?
    do {
        _ = try await backend.run(
            ExecutionRequest(
                command: "touch \(marker.path)", workingDir: nil,
                profile: BuiltInSandboxProfiles.networkedBuild, remote: remote))
        Issue.record("expected BackendError.unavailable to be thrown", sourceLocation: sourceLocation)
    } catch let BackendError.unavailable(text) {
        message = text
    } catch {
        Issue.record("expected BackendError.unavailable, got \(error)", sourceLocation: sourceLocation)
    }
    #expect(!FileManager.default.fileExists(atPath: marker.path), sourceLocation: sourceLocation)
    return message
}

@Suite("SSHBackend", .timeLimit(.minutes(1)))
struct SSHBackendTests {
    @Test func unavailableWhenNoResolverWired() async {
        let b = SSHBackend(resolveConnection: nil)
        #expect(await b.isAvailable() == false)
    }

    @Test func kindIsSSH() { #expect(SSHBackend(resolveConnection: nil).kind == .ssh) }

    // ---- Fail-closed: every way of not having a remote ----------------------
    // Each of these asserts BOTH that the run threw and that the command left
    // no local trace. The single most important invariant in this file: a
    // remote command must never fall through to running locally.

    @Test("no resolver at all (Leyline never wired) fails closed")
    func noResolverFailsClosed() async {
        let message = await expectBlockedWithNoLocalExecution(
            SSHBackend(resolveConnection: nil), remote: "prod-web")
        #expect(message?.localizedCaseInsensitiveContains("leyline") == true)
        #expect(message?.contains("not executed") == true)
    }

    @Test("an SSH run naming no connection fails closed")
    func noRemoteNamedFailsClosed() async {
        let message = await expectBlockedWithNoLocalExecution(
            SSHBackend(resolveConnection: succeeding()), remote: nil)
        #expect(message?.contains("names no connection") == true)
        // Blank/whitespace is treated as absent, not as an id.
        _ = await expectBlockedWithNoLocalExecution(
            SSHBackend(resolveConnection: succeeding()), remote: "   ")
    }

    /// The four resolver failures the user can actually hit, each surfacing its
    /// own reason rather than a generic "couldn't". The reason text originates
    /// in Leyline (`LeylineConnectionBridge`) and is passed through verbatim.
    @Test(
        "Leyline absent, unknown id, password-only and passphrase-protected each fail closed",
        arguments: [
            "No SSH connection provider is available — the Leyline app is not installed.",
            "leyline.resolve_connection: no saved connection has that id.",
            "Connection \"Legacy box\" authenticates with a password, and background execution "
                + "runs ssh with BatchMode=yes.",
            "Connection \"Staging box\" uses key \"Locked key\", which is passphrase-protected, "
                + "and background execution runs ssh with BatchMode=yes.",
        ])
    func resolverFailuresFailClosed(reason: String) async {
        let b = SSHBackend(resolveConnection: failing(reason))
        let message = await expectBlockedWithNoLocalExecution(b, remote: "some-id")
        // Actionable: the specific cause survives, and the user is told the
        // command did not run anywhere.
        #expect(message?.contains(reason) == true)
        #expect(message?.contains("not executed locally") == true)
    }

    // ---- The one path that does spawn --------------------------------------

    @Test func sshFailureSurfacesAsError() async throws {
        // Deterministic, no network: point sshPath at /usr/bin/false so the
        // "ssh" invocation exits non-zero — exactly what a real unreachable
        // host does (BatchMode=yes + ConnectTimeout=10 exit 255).
        var b = SSHBackend(resolveConnection: succeeding())
        b.sshPath = "/usr/bin/false"
        let r = try await b.run(
            ExecutionRequest(
                command: "echo hi", workingDir: nil,
                profile: BuiltInSandboxProfiles.networkedBuild,
                remote: "prod-web"))
        #expect(r.isError)  // failure surfaced, never a silent success
    }

    @Test("the resolver is called with the id the request named, per call")
    func resolvesPerRequest() async throws {
        let seen = SeenIDs()
        var b = SSHBackend(resolveConnection: { id in
            await seen.record(id)
            return .success(fakeConnection)
        })
        b.sshPath = "/usr/bin/false"
        for id in ["prod-web", "staging"] {
            _ = try await b.run(
                ExecutionRequest(
                    command: "echo hi", workingDir: nil,
                    profile: BuiltInSandboxProfiles.networkedBuild,
                    remote: id))
        }
        #expect(await seen.all == ["prod-web", "staging"])
    }
}

/// Collects the ids a resolver was asked for. An actor because the resolver is
/// `@Sendable` and runs off the MainActor.
private actor SeenIDs {
    private(set) var all: [String] = []
    func record(_ id: String) { all.append(id) }
}

/// The host end of `leyline.resolve_connection`, driven through a real
/// `AgentActionRegistryHub` with handlers registered by hand — no plugin, no
/// Keychain, no SSH.
@Suite("LeylineConnectionResolver", .timeLimit(.minutes(1)))
@MainActor
struct LeylineConnectionResolverTests {
    @Test("no registered handler (Leyline not installed) is an actionable failure")
    func leylineAbsent() async {
        let resolve = LeylineConnectionResolver.make(hub: AgentActionRegistryHub())
        guard case .failure(let f) = await resolve("prod-web") else {
            Issue.record("expected a failure with no handler registered")
            return
        }
        #expect(f.reason.contains("Leyline"))
        #expect(f.reason.contains("Install Leyline"))
    }

    @Test("an error reply is passed through verbatim, so the specific reason survives")
    func errorReplyPassedThrough() async {
        let hub = AgentActionRegistryHub()
        let reason = "Connection \"Legacy box\" authenticates with a password ... BatchMode=yes"
        _ = hub.register(appID: "leyline", actionID: LeylineConnectionResolver.actionID) { _ in
            AgentActionResult(text: reason, isError: true)
        }
        let resolve = LeylineConnectionResolver.make(hub: hub)
        guard case .failure(let f) = await resolve("legacy") else {
            Issue.record("expected a failure")
            return
        }
        #expect(f.reason == reason)
    }

    @Test("a well-formed reply decodes into SSHConnectionInfo, and the id is sent as JSON")
    func successDecodes() async {
        let hub = AgentActionRegistryHub()
        let asked = Box()
        _ = hub.register(appID: "leyline", actionID: LeylineConnectionResolver.actionID) { input in
            asked.value = input
            return AgentActionResult(
                text: #"{"host":"web.example.com","user":"deploy","port":2222,"identityPath":"/tmp/k"}"#,
                isError: false)
        }
        let resolve = LeylineConnectionResolver.make(hub: hub)
        guard case .success(let info) = await resolve("prod-web") else {
            Issue.record("expected a resolved connection")
            return
        }
        #expect(info.host == "web.example.com")
        #expect(info.user == "deploy")
        #expect(info.port == 2222)
        #expect(info.identityPath == "/tmp/k")
        // The id crosses as encoded JSON, so a quote in it cannot forge a field.
        #expect(asked.value == #"{"connection":"prod-web"}"#)
    }

    @Test("an undecodable reply is a failure, never a half-built connection")
    func garbageReplyIsFailure() async {
        let hub = AgentActionRegistryHub()
        _ = hub.register(appID: "leyline", actionID: LeylineConnectionResolver.actionID) { _ in
            AgentActionResult(text: "not json", isError: false)
        }
        guard case .failure = await LeylineConnectionResolver.make(hub: hub)("prod-web") else {
            Issue.record("expected a failure")
            return
        }
    }
}

@MainActor private final class Box { var value: String = "" }
