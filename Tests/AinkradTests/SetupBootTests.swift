import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

/// What launching into first-run setup establishes, independent of the keyboard
/// gate: the environment's starting flags, and the invariant that a provisional
/// home is never the one anything is pointed at.
///
/// These moved out of `SetupGateTests` when that suite was rewritten around
/// `SetupGate.swallows`. They never tested `swallows` — they test boot state —
/// and the provisional home never being adopted is a global constraint of the
/// setup plan, so the coverage is kept here rather than dropped.
@Suite("Setup boot")
@MainActor
struct SetupBootTests {
    @Test func bootingProvisionallyRaisesTheGateAndFlagsTheHome() throws {
        let t = TestHome.make("gate")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        // Defaults: an app booted onto a real Home is not gated.
        #expect(!environment.isSetupPresented)
        #expect(!environment.isProvisionalHome)

        // What `AinkradHostApp.init` does on `.unset`.
        environment.isProvisionalHome = true
        environment.isSetupPresented = true

        // The gate is raised over a workspace nothing else has opened.
        #expect(!environment.isLauncherPresented)
        #expect(!environment.isSettingsPresented)
    }

    @Test func aProvisionalHomeIsNeverPointedAt() throws {
        let home = LaunchHomeResolver.provisionalHome()
        let pointer = AinkradHome.defaultPointerDirectory()
            .appendingPathComponent("home.json")
        // The provisional home must not be the vault any pointer names.
        if let data = try? Data(contentsOf: pointer),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let path = json["path"] as? String
        {
            #expect(path != home.vaultRoot.path)
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: home.vaultRoot.appendingPathComponent(".ainkrad-home").path))
        // The invariant the gate exists to protect: a provisional home resolves to
        // a throwaway keychain namespace, so nothing authored may be written yet.
        #expect(home.isProvisional)
    }
}
