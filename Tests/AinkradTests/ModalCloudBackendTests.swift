import AinkradHostRuntime
// Tests/AinkradTests/ModalCloudBackendTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("ModalCloudBackend")
@MainActor
struct ModalCloudBackendTests {
    private func backend(
        configured: Bool,
        remoteExec: ModalCloudBackend.RemoteExec? = nil
    ) -> ModalCloudBackend {
        let creds = CloudCredentialsStore(secrets: InMemorySecretStore())
        if configured { creds.setCredential("tok", for: .modal) }
        let b = ModalCloudBackend(credentials: creds)
        if let remoteExec { b.remoteExec = remoteExec }
        return b
    }

    @Test func kindAndProvider() {
        let b = backend(configured: true)
        #expect(b.kind == .cloud)
        #expect(b.provider == .modal)
    }

    @Test func unconfiguredIsUnavailableAndBlocks() async {
        let b = backend(configured: false)
        #expect(await b.isAvailable() == false)
        await #expect(throws: BackendError.self) {
            _ = try await b.run(
                ExecutionRequest(
                    command: "ls", workingDir: nil,
                    profile: BuiltInSandboxProfiles.networkedBuild))
        }
    }

    @Test func defaultDriverBlocksEvenWhenConfigured() async {
        // The production default remoteExec throws unavailable until the
        // researched Modal driver lands — fail-closed, never host.
        let b = backend(configured: true)
        await #expect(throws: BackendError.self) {
            _ = try await b.run(
                ExecutionRequest(
                    command: "ls", workingDir: nil,
                    profile: BuiltInSandboxProfiles.networkedBuild))
        }
    }

    @Test func injectedDriverRunsAndHibernatesAfter() async throws {
        let b = backend(
            configured: true,
            remoteExec: { request, token in
                #expect(token == "tok")
                return ExecutionResult(
                    output: "remote:\(request.command)", exitCode: 0,
                    timedOut: false, unresponsive: false)
            })
        let r = try await b.run(
            ExecutionRequest(
                command: "ls", workingDir: nil,
                profile: BuiltInSandboxProfiles.networkedBuild))
        #expect(r.output == "remote:ls")
        #expect(b.state == .hibernating)  // hibernate-on-idle after the run
    }

    @Test func lifecycleStartsCold() {
        #expect(backend(configured: true).state == .cold)
    }

    @Test func hibernateReturnsToHibernating() async {
        let b = backend(configured: true)
        await b.hibernate()
        #expect(b.state == .hibernating)
    }
}
