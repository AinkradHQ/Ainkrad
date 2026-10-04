import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@Suite("DebugFixtureSeed")
struct DebugFixtureSeedTests {
    private func sandbox() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-seed-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("real sequence: resolve roots -> adopt -> seed produces complete setup")
    @MainActor
    func fullAdoptionAndSeedingProducesCompleteSetup() throws {
        let base = sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let lookup: ArgumentLookup = { @Sendable key in
            if key == "AinkradFixtureRoot" { return base.path }
            if key == "AinkradFixtureSeed" { return "1" }
            return nil
        }

        // 1. Resolve roots (must NOT seed before adopt, leaves Vault empty for adoption)
        let roots = try #require(try resolveDebugFixtureRoots(lookup))

        // 2. Adopt via resolver fixture path
        let home = try LaunchHomeResolver.adopt(
            roots.defaultVaultRoot,
            pointerDirectory: roots.pointerDirectory,
            cacheRoot: roots.cacheRoot,
            legacyContainer: nil
        )

        // 3. Seed into adopted Home
        seedDebugFixtureIfNeeded(home: home, lookup: lookup)

        // 4. SetupCoordinator reports complete
        let vaultConfig = home.vaultRoot.appendingPathComponent("Config", isDirectory: true)
        let persistence = FileDocumentStore(rootURL: vaultConfig)

        let setupDoc = try #require(persistence.load(SetupDocument.self))
        #expect(setupDoc.completedAt != nil)
        #expect(setupDoc.setupVersion == SetupCoordinator.currentSetupVersion)

        let coordinator = SetupCoordinator(persistence: persistence, isProvisionalHome: false)
        #expect(coordinator.isComplete)
        #expect(!SetupGate.raisedAtLaunch(provisionalHome: false, setupIsComplete: coordinator.isComplete))
    }

    @Test("seeding twice is idempotent and does not overwrite modified setup/settings")
    @MainActor
    func seedingIsIdempotent() throws {
        let base = sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let lookup: ArgumentLookup = { @Sendable key in
            if key == "AinkradFixtureRoot" { return base.path }
            if key == "AinkradFixtureSeed" { return "1" }
            return nil
        }

        let roots = try #require(try resolveDebugFixtureRoots(lookup))
        let home = try LaunchHomeResolver.adopt(
            roots.defaultVaultRoot,
            pointerDirectory: roots.pointerDirectory,
            cacheRoot: roots.cacheRoot,
            legacyContainer: nil
        )
        seedDebugFixtureIfNeeded(home: home, lookup: lookup)

        let vaultConfig = home.vaultRoot.appendingPathComponent("Config", isDirectory: true)
        let persistence = FileDocumentStore(rootURL: vaultConfig)

        var settings = try #require(persistence.load(GlobalSettings.self))
        settings.theme = .cyberPurple
        persistence.save(settings)

        // Seed again over existing adopted Home
        seedDebugFixtureIfNeeded(home: home, lookup: lookup)

        let reloadedSettings = try #require(persistence.load(GlobalSettings.self))
        #expect(reloadedSettings.theme == .cyberPurple)
    }

    @Test("seeding with seed flag alone ignores seeding and makes no writes outside fixture")
    func seedFlagWithoutRootIsIgnored() throws {
        let lookup: ArgumentLookup = { @Sendable key in
            if key == "AinkradFixtureSeed" { return "1" }
            return nil
        }

        #expect(try resolveDebugFixtureRoots(lookup) == nil)
        seedDebugFixtureIfNeeded(home: nil, lookup: lookup)
    }
}
