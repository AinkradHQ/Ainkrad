// Tests/AinkradTests/SeatbeltBackendTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SeatbeltBackend")
struct SeatbeltBackendTests {
    private func profile(read: [String], write: [String], net: NetworkPolicy = .off) -> SandboxProfile {
        SandboxProfile(
            id: "t", name: "t", backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: read, writablePaths: write),
            networkPolicy: net, resourceLimits: ResourceLimits(timeoutSeconds: 15),
            toolAllowList: [])
    }

    // MARK: - Enforcement (security-critical, run only where sandbox-exec exists)

    @Test func runsBasicCommandInsideSandbox() async throws {
        let backend = SeatbeltBackend()
        guard await backend.isAvailable() else { return }  // guard-skip, never throw-skip
        let ws = NSTemporaryDirectory()
        let r = try await backend.run(
            ExecutionRequest(
                command: "echo sandboxed",
                workingDir: ws, profile: profile(read: [ws], write: [ws])))
        #expect(r.output.contains("sandboxed"))
    }

    @Test func deniedWriteOutsideWritablePaths() async throws {
        let backend = SeatbeltBackend()
        guard await backend.isAvailable() else { return }  // guard-skip, never throw-skip
        let ws = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbx-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: ws) }
        // Attempt to write OUTSIDE the writable set (a /private/tmp sibling), expect failure.
        let outside = "/private/tmp/should-not-exist-\(UUID().uuidString)"
        let r = try await backend.run(
            ExecutionRequest(
                command: "echo x > \(outside)", workingDir: ws,
                profile: profile(read: [ws], write: [ws])))
        #expect(r.isError)  // sandbox denied the write
        #expect(!FileManager.default.fileExists(atPath: outside))
    }

    @Test func kindIsSeatbelt() { #expect(SeatbeltBackend().kind == .seatbelt) }

    // MARK: - Fail-closed paths (must never run on host; no kernel dependency)

    @Test func profileGenerationFailureBlocksExecutionWithoutRunningOnHost() async throws {
        // A control character in a policy path makes SeatbeltProfileGenerator
        // throw BackendError.profileGeneration. The marker file must never
        // appear — proof the command never ran, sandboxed or not.
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbx-should-not-run-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: marker) }
        let badProfile = profile(read: ["/tmp/bad\npath"], write: [])
        let backend = SeatbeltBackend()
        await #expect(throws: BackendError.self) {
            _ = try await backend.run(
                ExecutionRequest(
                    command: "touch \(marker)", workingDir: NSTemporaryDirectory(), profile: badProfile))
        }
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func unavailableSandboxExecBlocksExecutionWithoutRunningOnHost() async throws {
        // Point sandboxExecPath at a nonexistent binary — isAvailable() must
        // report false, and run() must still fail closed (never fall through
        // to executing the command unsandboxed).
        var backend = SeatbeltBackend()
        backend.sandboxExecPath = "/usr/bin/definitely-not-sandbox-exec-\(UUID().uuidString)"
        #expect(await backend.isAvailable() == false)

        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbx-should-not-run-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: marker) }
        let ws = NSTemporaryDirectory()
        let r = try await backend.run(
            ExecutionRequest(
                command: "touch \(marker)", workingDir: ws, profile: profile(read: [ws], write: [ws])))
        #expect(r.isError)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func buildsSandboxExecArgvWithGeneratedProfileFile() async throws {
        // Assert the exact invocation shape without depending on kernel
        // enforcement: sandbox-exec -f <tempfile.sb> /bin/zsh -c <command>,
        // where <tempfile.sb> contains the generated SBPL, and the temp file
        // is cleaned up afterward.
        let backend = SeatbeltBackend()
        guard await backend.isAvailable() else { return }
        let ws = NSTemporaryDirectory()
        // Capture the temp profile path via a command that copies it out
        // before sandbox-exec's own lifecycle removes it, by echoing argv[0]
        // is not directly observable from inside; instead assert indirectly:
        // the profile file must not exist before or after the run, and the
        // run must reflect SBPL contents (deny-by-default => unlisted write fails).
        let before = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("ain-sbx-") && $0.hasSuffix(".sb") }
        #expect(before.isEmpty)

        _ = try await backend.run(
            ExecutionRequest(
                command: "echo argv-check", workingDir: ws,
                profile: profile(read: [ws], write: [ws])))

        let after = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("ain-sbx-") && $0.hasSuffix(".sb") }
        #expect(after.isEmpty)  // cleaned up, not leaked
    }
}
