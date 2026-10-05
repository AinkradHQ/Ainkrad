// Tests/AinkradTests/HostBackendTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("HostBackend")
struct HostBackendTests {
    private func req(_ cmd: String, timeout: Int = 10) -> ExecutionRequest {
        var p = BuiltInSandboxProfiles.hostTrusted
        p.resourceLimits = ResourceLimits(timeoutSeconds: timeout)
        return ExecutionRequest(command: cmd, workingDir: nil, profile: p)
    }

    @Test func isAlwaysAvailable() async {
        #expect(await HostBackend().isAvailable())
    }

    @Test func runsCommandOnHost() async throws {
        let r = try await HostBackend().run(req("echo hostcheck"))
        #expect(r.output.contains("hostcheck"))
        #expect(r.exitCode == 0)
    }

    @Test func kindIsHost() {
        #expect(HostBackend().kind == .host)
    }

    @Test func propagatesNonZeroExitCode() async throws {
        let r = try await HostBackend().run(req("exit 7"))
        #expect(r.exitCode == 7)
        #expect(r.isError)
    }
}
