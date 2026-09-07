import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

@MainActor
@Suite("Pairing the CLI")
struct SignalCLIPairingTests {
    private func tempConfig() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-\(UUID().uuidString.prefix(8))")
            .appendingPathComponent("cli-signal.json")
    }

    @Test("pairing mints a token the registry resolves")
    func mintsOnFirstRun() throws {
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())

        #expect(SignalCLIPairing.ensurePaired(registry: registry, configURL: url))
        let config = try JSONDecoder().decode(
            [String: String].self, from: try Data(contentsOf: url))
        let token = try #require(config["token"])
        #expect(registry.source(for: token) == .host)
    }

    @Test("pairing again does NOT rotate a token that still works")
    func doesNotRotateAGoodToken() throws {
        // The bug this guards: minting on every bootstrap invalidates the
        // token already sitting in the user's git hook, so notifications work
        // until the next launch and then stop for no visible reason.
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())

        #expect(SignalCLIPairing.ensurePaired(registry: registry, configURL: url))
        let first = try JSONDecoder().decode(
            [String: String].self, from: try Data(contentsOf: url))["token"]

        #expect(SignalCLIPairing.ensurePaired(registry: registry, configURL: url) == false)
        let second = try JSONDecoder().decode(
            [String: String].self, from: try Data(contentsOf: url))["token"]
        #expect(first == second)
    }

    @Test("a stale token in the config is replaced")
    func replacesStaleToken() throws {
        // After the Keychain entry is gone — revoked, or a fresh Mac restored
        // from a vault copy — the file still holds a token nothing resolves.
        // Left alone, the CLI would report `rejected` forever.
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try JSONEncoder().encode(["token": "stale"]).write(to: url)

        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        #expect(SignalCLIPairing.ensurePaired(registry: registry, configURL: url))
        let token = try #require(try JSONDecoder().decode(
            [String: String].self, from: try Data(contentsOf: url))["token"])
        #expect(token != "stale")
        #expect(registry.source(for: token) == .host)
    }

    @Test("the config file is owner-only")
    func configIsOwnerOnly() throws {
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        SignalCLIPairing.ensurePaired(registry: SignalTokenRegistry(secrets: InMemorySecretStore()),
                                      configURL: url)
        let mode = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            as? NSNumber)?.intValue ?? 0
        #expect(mode == 0o600, "a readable credential file is a leaked credential")
    }
}
