// Tests/AinkradTests/DockerArgsBuilderTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("DockerArgsBuilder")
struct DockerArgsBuilderTests {
    private func profile(
        fs: FilesystemPolicy, net: NetworkPolicy,
        mem: Int? = nil, cpu: Int? = nil
    ) -> SandboxProfile {
        SandboxProfile(
            id: "d", name: "d", backend: .docker,
            fsPolicy: fs,
            networkPolicy: net,
            resourceLimits: ResourceLimits(cpuCount: cpu, memoryMB: mem, timeoutSeconds: 60),
            toolAllowList: [])
    }

    @Test func networkOffAddsNetworkNone() {
        let p = profile(fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]), net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "--network" && $1 == "none" })
    }

    @Test func networkOnUsesBridge() {
        let p = profile(fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]), net: .on)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "--network" && $1 == "bridge" })
    }

    @Test func networkAllowListFailsClosedToNetworkNone() {
        // Docker has no hostname-level egress filter, so an allow-list
        // (unlike a blanket `.on`) must fail CLOSED to `--network none` —
        // matching SeatbeltProfileGenerator's posture for this same
        // un-filterable case — rather than silently degrading to full bridge.
        let p = profile(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]),
            net: .allowList(["example.com"]))
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "--network" && $1 == "none" })
        #expect(!zip(args, args.dropFirst()).contains { $0 == "--network" && $1 == "bridge" })
    }

    @Test func mountsWorkdirAndSetsWorkdirFlag() {
        let p = profile(fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]), net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "-v" && $1 == "/ws:/ws" })
        #expect(zip(args, args.dropFirst()).contains { $0 == "-w" && $1 == "/ws" })
        #expect(args.contains("img"))
    }

    @Test func readablePathsMountedReadOnly() {
        let p = profile(
            fs: FilesystemPolicy(readablePaths: ["/opt/ro-dep"], writablePaths: ["<workspace>"]),
            net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "-v" && $1 == "/opt/ro-dep:/opt/ro-dep:ro" })
    }

    @Test func writablePathsMountedReadWrite() {
        let p = profile(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>", "/opt/rw-cache"]),
            net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "-v" && $1 == "/opt/rw-cache:/opt/rw-cache" })
        // Never also mounted read-only.
        #expect(!zip(args, args.dropFirst()).contains { $0 == "-v" && $1 == "/opt/rw-cache:/opt/rw-cache:ro" })
    }

    @Test func pathNotInPolicyIsNotMounted() {
        let p = profile(
            fs: FilesystemPolicy(readablePaths: ["/opt/allowed"], writablePaths: ["<workspace>"]),
            net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        let joined = args.joined(separator: "\u{0}")
        #expect(!joined.contains("/etc/secret"))
        #expect(!args.contains("/etc/secret:/etc/secret"))
        #expect(!args.contains("/etc/secret:/etc/secret:ro"))
    }

    @Test func appliesResourceLimits() {
        let p = profile(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]),
            net: .on, mem: 512, cpu: 2)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(zip(args, args.dropFirst()).contains { $0 == "--memory" && $1 == "512m" })
        #expect(zip(args, args.dropFirst()).contains { $0 == "--cpus" && $1 == "2" })
    }

    @Test func absentResourceLimitsOmitFlags() {
        let p = profile(fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]), net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(!args.contains("--memory"))
        #expect(!args.contains("--cpus"))
    }

    @Test func commandIsASingleTrailingArgvElement_noInjection() {
        // A command containing shell metacharacters / a fake docker flag must
        // stay ONE argv element — never shell-concatenated into the array —
        // so it can't inject an extra docker flag or split into new args.
        let injected = "ls; --privileged #"
        let p = profile(fs: FilesystemPolicy(readablePaths: [], writablePaths: ["<workspace>"]), net: .off)
        let args = DockerArgsBuilder.runArgs(command: injected, profile: p, workspacePath: "/ws", image: "img")
        #expect(args.last == injected)
        #expect(!args.contains("--privileged"))
        // Exactly one occurrence of the raw string, as a single element.
        #expect(args.filter { $0 == injected }.count == 1)
    }

    @Test func deterministicForSameInput() {
        let p = profile(
            fs: FilesystemPolicy(readablePaths: ["/opt/a"], writablePaths: ["<workspace>", "/opt/b"]),
            net: .on, mem: 256, cpu: 1)
        let a = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        let b = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(a == b)
    }

    @Test func invalidPolicyPathIsSkippedNotMounted() {
        // Non-absolute path: fail-closed, silently skipped rather than mounted.
        let p = profile(
            fs: FilesystemPolicy(readablePaths: ["relative/path"], writablePaths: ["<workspace>"]),
            net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(!args.contains { $0.contains("relative/path") })
    }

    @Test func pathContainingColonIsSkippedNotMounted() {
        // A colon in a mount source collides with docker's `-v
        // source:dest:mode` separator and would produce a malformed/
        // misinterpreted triple. Fail-closed: skip the mount entirely rather
        // than emit it, matching SeatbeltProfileGenerator.resolve's rigor.
        let p = profile(
            fs: FilesystemPolicy(
                readablePaths: ["/opt/weird:path"],
                writablePaths: ["<workspace>", "/opt/other:weird"]),
            net: .off)
        let args = DockerArgsBuilder.runArgs(command: "ls", profile: p, workspacePath: "/ws", image: "img")
        #expect(!args.contains { $0.contains("/opt/weird:path") })
        #expect(!args.contains { $0.contains("/opt/other:weird") })
    }
}
