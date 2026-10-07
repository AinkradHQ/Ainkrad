import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Storage isolation")
@MainActor
struct StorageIsolationTests {
    @Test func bootstrapPlacesEverySubsystemInsideTheHome() throws {
        let t = TestHome.make("iso")
        defer { t.cleanup() }

        _ = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: t.home.shared(.config).path))
        #expect(fm.fileExists(atPath: t.home.shared(.skills).path))
        #expect(fm.fileExists(atPath: t.home.shared(.memory).path))
        #expect(fm.fileExists(atPath: t.home.shared(.commands).path))
        #expect(fm.fileExists(atPath: t.home.cacheRoot.appendingPathComponent("Checkpoints").path))
    }

    @Test func bootstrapTouchesNothingInTheLiveApplicationSupportTree() throws {
        let t = TestHome.make("iso2")
        defer { t.cleanup() }

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        let live = support.appendingPathComponent(bundleID, isDirectory: true)
        let watched = ["Documents", "Shares", "Checkpoints", "Commands", "GeneratedMedia", "Skills", "Memory"]
        let before = watched.map { fm.fileExists(atPath: live.appendingPathComponent($0).path) }

        _ = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let after = watched.map { fm.fileExists(atPath: live.appendingPathComponent($0).path) }
        #expect(before == after)
    }
}
