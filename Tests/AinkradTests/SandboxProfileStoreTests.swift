import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("SandboxProfileStore")
@MainActor
struct SandboxProfileStoreTests {
    @Test func exposesBuiltInsIncludingDefaults() {
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        #expect(store.profile(id: BuiltInSandboxProfiles.mainID)?.backend == .host)
        let dflt = store.profile(id: BuiltInSandboxProfiles.defaultNonMainID)
        #expect(dflt?.backend == .seatbelt)
        #expect(dflt?.networkPolicy == .off)
    }

    @Test func builtInsHaveCorrectRestrictivePolicies() {
        let all = BuiltInSandboxProfiles.all

        let host = BuiltInSandboxProfiles.hostTrusted
        #expect(host.id == "host-trusted")
        #expect(host.backend == .host)
        #expect(host.networkPolicy == .on)
        #expect(host.allowHostOverride == false)

        let readOnly = BuiltInSandboxProfiles.readOnly
        #expect(readOnly.id == "read-only")
        #expect(readOnly.backend == .seatbelt)
        #expect(!readOnly.fsPolicy.readablePaths.isEmpty)
        #expect(readOnly.fsPolicy.writablePaths.isEmpty)
        #expect(readOnly.networkPolicy == .off)

        let workspaceWrite = BuiltInSandboxProfiles.workspaceWrite
        #expect(workspaceWrite.id == "workspace-write")
        #expect(workspaceWrite.backend == .seatbelt)
        #expect(!workspaceWrite.fsPolicy.readablePaths.isEmpty)
        #expect(!workspaceWrite.fsPolicy.writablePaths.isEmpty)
        #expect(workspaceWrite.networkPolicy == .off)

        let networkedBuild = BuiltInSandboxProfiles.networkedBuild
        #expect(networkedBuild.id == "networked-build")
        #expect(networkedBuild.backend == .seatbelt)
        #expect(networkedBuild.networkPolicy == .on)
        #expect(!networkedBuild.fsPolicy.writablePaths.isEmpty)

        #expect(all.count == 4)
        #expect(Set(all.map(\.id)).count == 4)
    }

    @Test func upsertPersistsUserProfile() {
        let p = InMemoryPersistenceStore()
        let store = SandboxProfileStore(persistence: p)
        let custom = SandboxProfile(
            id: "mine", name: "Mine", backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .off, resourceLimits: ResourceLimits(timeoutSeconds: 10),
            toolAllowList: [])
        store.upsert(custom)
        // A fresh store over the same persistence sees it.
        #expect(SandboxProfileStore(persistence: p).profile(id: "mine")?.name == "Mine")
    }

    @Test func upsertCannotShadowBuiltIn() {
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        var evil = BuiltInSandboxProfiles.hostTrusted
        evil.backend = .host  // attempt to redefine host-trusted
        evil.name = "hijacked"
        store.upsert(evil)
        #expect(store.profile(id: BuiltInSandboxProfiles.mainID)?.name != "hijacked")
    }

    @Test func deleteRemovesUserProfileOnly() {
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        let custom = SandboxProfile(
            id: "mine", name: "Mine", backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .off, resourceLimits: ResourceLimits(timeoutSeconds: 10),
            toolAllowList: [])
        store.upsert(custom)
        store.delete(id: "mine")
        #expect(store.profile(id: "mine") == nil)
        store.delete(id: BuiltInSandboxProfiles.mainID)  // no-op
        #expect(store.profile(id: BuiltInSandboxProfiles.mainID) != nil)
    }

    @Test func allReturnsBuiltInsFirstThenUserDefined() {
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        let custom = SandboxProfile(
            id: "mine", name: "Mine", backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .off, resourceLimits: ResourceLimits(timeoutSeconds: 10),
            toolAllowList: [])
        store.upsert(custom)
        let all = store.all()
        #expect(all.count == 5)
        #expect(Array(all.prefix(4).map(\.id)) == BuiltInSandboxProfiles.all.map(\.id))
        #expect(all.last?.id == "mine")
    }

    // MARK: - Fail-closed decode (carry-over from Task 1)

    @Test func malformedUserProfileIsDroppedNotCrashingAndNeverFallsOpen() throws {
        // One well-formed profile, one with fsPolicy/networkPolicy missing entirely
        // (Task 1 decodes those as REQUIRED, so the malformed entry throws on decode).
        let json = """
            {
              "userDefined": [
                {
                  "id": "good",
                  "name": "Good",
                  "backend": "seatbelt",
                  "fsPolicy": {"readablePaths": [], "writablePaths": []},
                  "networkPolicy": {"off": {}},
                  "resourceLimits": {"timeoutSeconds": 10},
                  "toolAllowList": []
                },
                {
                  "id": "bad",
                  "name": "Bad"
                }
              ]
            }
            """.data(using: .utf8)!

        let doc = try JSONDecoder().decode(SandboxProfileDocument.self, from: json)

        // The good profile survives.
        #expect(doc.userDefined.contains { $0.id == "good" })
        // The malformed one is dropped, not crashed on and not silently upgraded
        // to something permissive/host-backed.
        #expect(!doc.userDefined.contains { $0.id == "bad" })
        #expect(doc.userDefined.allSatisfy { $0.backend != .host })

        // Wiring it through the store: no crash, no permissive fallback, good data intact.
        let p = InMemoryPersistenceStore()
        p.save(doc)
        let store = SandboxProfileStore(persistence: p)
        #expect(store.profile(id: "good") != nil)
        #expect(store.profile(id: "bad") == nil)
        // Built-ins remain untouched by the malformed entry.
        #expect(store.profile(id: BuiltInSandboxProfiles.mainID)?.backend == .host)
    }

    @Test func entirelyMalformedUserDefinedFallsBackWithoutCrashing() throws {
        // userDefined present but not an array of profiles at all — must not crash,
        // must not yield a permissive default; falling back to no user profiles is fine.
        let json = """
            {"userDefined": "not-an-array"}
            """.data(using: .utf8)!
        let doc = try JSONDecoder().decode(SandboxProfileDocument.self, from: json)
        #expect(doc.userDefined.isEmpty)

        let p = InMemoryPersistenceStore()
        p.save(doc)
        let store = SandboxProfileStore(persistence: p)
        #expect(store.profile(id: BuiltInSandboxProfiles.mainID)?.backend == .host)
        #expect(store.all().allSatisfy { BuiltInSandboxProfiles.reservedIDs.contains($0.id) })
    }
}
