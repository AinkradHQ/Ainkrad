// Tests/AinkradTests/DockerBackendTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("DockerBackend")
struct DockerBackendTests {
    @Test func kindIsDocker() {
        #expect(DockerBackend().kind == .docker)
    }

    @Test func unavailableWhenDockerMissing() async {
        // Empty out BOTH resolution inputs so resolution provably fails even on
        // a dev box with Docker installed — deterministic, spawns nothing.
        var b = DockerBackend()
        b.dockerPath = "/nonexistent/docker"
        b.fallbackPaths = []
        #expect(await b.isAvailable() == false)
    }

    @Test func runThrowsUnavailableWithGuidance_commandNeverRunsOnHost() async {
        var b = DockerBackend()
        b.dockerPath = "/nonexistent/docker"
        b.fallbackPaths = []
        let profile = BuiltInSandboxProfiles.networkedBuild
        // A marker file the (never-run) command would create on the host if
        // any fall-through path existed. Its absence after the throw proves
        // the command was blocked, not executed unsandboxed.
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("ain-docker-fail-closed-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: marker) }

        await #expect(throws: BackendError.self) {
            _ = try await b.run(
                ExecutionRequest(
                    command: "touch \(marker.path)",
                    workingDir: "/tmp",
                    profile: profile))
        }

        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func runThrowsUnavailableErrorCarriesGuidanceText() async {
        var b = DockerBackend()
        b.dockerPath = "/nonexistent/docker"
        b.fallbackPaths = []
        let profile = BuiltInSandboxProfiles.networkedBuild
        do {
            _ = try await b.run(ExecutionRequest(command: "ls", workingDir: "/tmp", profile: profile))
            Issue.record("expected BackendError.unavailable to be thrown")
        } catch let BackendError.unavailable(message) {
            #expect(message.localizedCaseInsensitiveContains("docker"))
        } catch {
            Issue.record("expected BackendError.unavailable, got \(error)")
        }
    }
}
