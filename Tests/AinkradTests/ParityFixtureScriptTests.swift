import Testing
import Foundation
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
@testable import Ainkrad

/// Runs `scripts/parity-fixture.sh` and decodes what it wrote with the host's own types, so a
/// format change in the app breaks here instead of silently emptying the parity fixture.
@Suite("ParityFixtureScript")
struct ParityFixtureScriptTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/parity-fixture.sh")

    private func run(_ dir: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Self.script.path, dir.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("parity-fixture-test-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
    }

    @Test("seeds documents the host decodes, is idempotent, and refuses unsafe dirs")
    @MainActor
    func seedsDecodableFixture() throws {
        let fix = tempDir()
        defer { try? FileManager.default.removeItem(at: fix) }
        #expect(try run(fix) == 0)
        #expect(try run(fix) == 0)   // idempotent: wipes and reseeds

        let vault = fix.appendingPathComponent("Vault", isDirectory: true)
        #expect(try HomeMarker.read(in: vault) != nil)
        let store = FileDocumentStore(rootURL: vault.appendingPathComponent("Config"))

        let settings = try #require(store.load(GlobalSettings.self))
        #expect(settings.skyMotionEnabled == false)
        #expect(settings.restoreLayoutOnLaunch)

        let setup = try #require(store.load(SetupDocument.self))
        #expect(setup.setupVersion == SetupCoordinator.currentSetupVersion)
        #expect(SetupCoordinator(persistence: store, isProvisionalHome: false).isComplete)

        let layout = try #require(store.load(LayoutStateSnapshot.self))
        #expect(layout.workspaces.count == 2)
        let launch = layout.launchState(restoringPanes: true)
        #expect(launch.workspaces.count == 2)   // the named workspace survives launchState
        func leaves(_ n: PaneNode?) -> Int {
            switch n {
            case .leaf?: return 1
            case .split(_, let c, _)?: return c.map { leaves($0) }.reduce(0, +)
            case nil: return 0
            }
        }
        #expect(launch.workspaces.compactMap { $0.root?.makeNode() }.map(leaves).reduce(0, +) == 3)

        let pins = try #require(store.load(HoardPinnedRootsDocument.self))
        #expect(pins.paths.count == 1)
        #expect(pins.paths[0].hasSuffix(fix.lastPathComponent + "/Hoard"))   // script resolves /var -> /private/var
        #expect(try FileManager.default.contentsOfDirectory(atPath: pins.paths[0]).count >= 3)
        #expect(store.load(HoardPaneDocument.self)?.tabPaths == pins.paths)

        let catalog = try JSONDecoder().decode(RemoteCatalog.self,
            from: Data(contentsOf: fix.appendingPathComponent("catalog.json")))
        #expect(catalog.apps.count == 3)

        let signals = try SignalStore(url: fix.appendingPathComponent("signal.sqlite"))
        let events = signals.page(filter: SignalFilter(), before: nil, limit: 100)
        #expect(events.count == 12)
        #expect(Set(events.map(\.source)).count == 3)
        #expect(events.contains { signals.dedupeCount(id: $0.id) > 1 })
        let prefs = SignalPreferencesStore(url: fix.appendingPathComponent("signal-preferences.json")).load()
        #expect(prefs.retention.maxAgeDays > 365)

        // Refuses: a non-fixture non-empty dir, and the real Home.
        let other = tempDir()
        defer { try? FileManager.default.removeItem(at: other) }
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "x".write(to: other.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        #expect(try run(other) != 0)
        #expect(FileManager.default.fileExists(atPath: other.appendingPathComponent("keep.txt").path))
        #expect(try run(FileManager.default.homeDirectoryForCurrentUser) != 0)
        #expect(try run(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Ainkrad/x")) != 0)
    }

    #if DEBUG
    @Test("a fixture launch reads the catalog from the fixture root; no fixture means the hosted URL")
    func catalogURLFollowsFixtureRoot() throws {
        let fix = tempDir()
        defer { try? FileManager.default.removeItem(at: fix) }
        let roots = try #require(try resolveDebugFixtureRoots { @Sendable key in
            key == "AinkradFixtureRoot" ? fix.path : nil
        })
        #expect(fixtureCatalogURL(in: roots).lastPathComponent == "catalog.json")
        #expect(fixtureCatalogURL(in: roots).deletingLastPathComponent().standardizedFileURL.path == fix.standardizedFileURL.path)
        #expect(defaultHostCatalogURL() == remoteCatalogURL)   // the test process has no fixture arg
    }
    #endif
}
