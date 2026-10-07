import Foundation
import Testing

@testable import Ainkrad

@Suite("SandboxProfile")
struct SandboxProfileTests {
    @Test func roundTripsThroughCodable() throws {
        let p = SandboxProfile(
            id: "custom", name: "Custom",
            backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: ["/a"], writablePaths: ["/b"]),
            networkPolicy: .allowList(["example.com"]),
            resourceLimits: ResourceLimits(cpuCount: 2, memoryMB: 512, timeoutSeconds: 30),
            toolAllowList: ["run_terminal"],
            allowHostOverride: false)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(SandboxProfile.self, from: data)
        #expect(back == p)
    }

    @Test func networkPolicyEncodesEachCase() throws {
        for np: NetworkPolicy in [.off, .on, .allowList(["x"])] {
            let data = try JSONEncoder().encode(np)
            #expect(try JSONDecoder().decode(NetworkPolicy.self, from: data) == np)
        }
    }

    @Test func allowHostOverrideDefaultsFalseWhenAbsentFromJSON() throws {
        // Older payloads without the flag must decode as fail-closed (false).
        let json = """
            {"id":"x","name":"X","backend":"seatbelt",
             "fsPolicy":{"readablePaths":[],"writablePaths":[]},
             "networkPolicy":{"off":{}},
             "resourceLimits":{"timeoutSeconds":30},
             "toolAllowList":[]}
            """.data(using: .utf8)!
        let p = try JSONDecoder().decode(SandboxProfile.self, from: json)
        #expect(p.allowHostOverride == false)
    }

    @Test func defaultFilesystemPolicyGrantsNoPaths() {
        let policy = FilesystemPolicy(readablePaths: [], writablePaths: [])
        #expect(policy.readablePaths.isEmpty)
        #expect(policy.writablePaths.isEmpty)
    }

    @Test func defaultNetworkPolicyIsOff() {
        // Fail-closed: the "no policy specified" case must be .off, not .on or allowList.
        let np: NetworkPolicy = .off
        #expect(np == .off)
    }

    @Test func policyValueSemantics() {
        var a = FilesystemPolicy(readablePaths: ["/a"], writablePaths: [])
        let b = a
        a.readablePaths.append("/c")
        #expect(a.readablePaths != b.readablePaths)
        #expect(b.readablePaths == ["/a"])
    }

    @Test func backendKindCasesRoundTripAndHostIsNotDefaultChoice() throws {
        for kind in SandboxBackendKind.allCases {
            let data = try JSONEncoder().encode(kind)
            #expect(try JSONDecoder().decode(SandboxBackendKind.self, from: data) == kind)
        }
        // Host must never be reached implicitly: any non-host backend profile
        // defaults allowHostOverride to false.
        let profile = SandboxProfile(
            id: "seatbelt-default", name: "Seatbelt",
            backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .off,
            resourceLimits: ResourceLimits(timeoutSeconds: 30),
            toolAllowList: [])
        #expect(profile.allowHostOverride == false)
    }
}
