import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

/// Guards the seam that keeps the test suite out of the developer's real Keychain.
///
/// Secrets are not vault-resident, so `Home` does not obviously govern them — which
/// is exactly why this needs a test rather than a comment. `bootstrap` namespaces
/// every Keychain item by `home.keychainServiceName`; if that derivation ever
/// collapses to one shared value, a test writing a connection's API key silently
/// lands in the real `com.ainkrad.app` service.
///
/// The derivation must fail *safe*, in one specific direction: an unrecognized vault
/// path resolves to the canonical service (the user's keys keep working), and only a
/// vault in a throwaway location gets its own namespace. The reverse — an allowlist of
/// known-good roots — would orphan every saved API key the moment a user picked a
/// folder nobody had thought of. `anArbitraryUserChosenVaultKeepsTheCanonicalService`
/// is the test for that, and is the case the first implementation got wrong.
@Suite("Home keychain service")
struct HomeKeychainServiceTests {
    private func home(vault: URL) -> Home {
        Home(vaultRoot: vault, cacheRoot: vault.appendingPathComponent("cache", isDirectory: true))
    }

    /// Requirement 1, the case that matters most: the wizard lets the user put their
    /// vault anywhere, and every one of those places must resolve to the canonical
    /// service. These are paths no allowlist could have anticipated.
    @Test func anArbitraryUserChosenVaultKeepsTheCanonicalService() {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let arbitrary = [
            userHome.appendingPathComponent("Documents/My Ainkrad Vault", isDirectory: true),
            userHome.appendingPathComponent("Dropbox/work/ainkrad", isDirectory: true),
            userHome.appendingPathComponent("Библиотека/хранилище", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/ExternalSSD/Ainkrad", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Ainkrad", isDirectory: true),
            // Named like a temp dir but not in one — must NOT take the isolated branch.
            userHome.appendingPathComponent("tmp/Ainkrad", isDirectory: true),
            URL(fileURLWithPath: "/tmpfoo/Ainkrad", isDirectory: true),
        ]
        #expect(!arbitrary.isEmpty)
        for vault in arbitrary {
            #expect(
                home(vault: vault).keychainServiceName == Home.canonicalKeychainService,
                "a user-chosen vault at \(vault.path) must keep the canonical service")
        }
    }

    /// Requirement 1, the two locations the app itself picks: `~/Ainkrad` (Task 8's
    /// adoption target) and the pre-Home Application Support container (the interim
    /// root `AinkradHostApp.init` passes). Both are covered by the general rule above
    /// rather than by any special case, but they are the paths existing users' secrets
    /// are actually stored against, so they get their own assertion.
    @Test func theAppsOwnVaultLocationsKeepTheCanonicalService() throws {
        let defaultVault = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Ainkrad", isDirectory: true)
        #expect(home(vault: defaultVault).keychainServiceName == Home.canonicalKeychainService)

        let support = try #require(
            FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let container =
            support
            .appendingPathComponent(Home.canonicalKeychainService, isDirectory: true)
        #expect(home(vault: container).keychainServiceName == Home.canonicalKeychainService)
    }

    /// Requirement 2: two throwaway vaults never share a namespace, so two suites
    /// running against `TestHome.make()` cannot see each other's secrets. Asserted
    /// against the helper the whole suite actually uses, not a hand-built path — if
    /// `TestHome` ever produced vaults outside the temp tree this would catch it.
    @Test func twoDifferentTempVaultsGetDifferentServiceNames() {
        let a = TestHome.make("kc-a")
        defer { a.cleanup() }
        let b = TestHome.make("kc-b")
        defer { b.cleanup() }

        #expect(Home.isThrowawayLocation(a.home.vaultRoot))
        #expect(Home.isThrowawayLocation(b.home.vaultRoot))
        #expect(a.home.keychainServiceName != b.home.keychainServiceName)
        #expect(a.home.keychainServiceName != Home.canonicalKeychainService)
        #expect(b.home.keychainServiceName != Home.canonicalKeychainService)
    }

    /// Every spelling of the temp directory must take the isolated branch — the tests
    /// in this repo and in AinkradAppKit build temp paths several different ways, and
    /// on macOS `/tmp`, `/private/tmp`, `$TMPDIR` and `/var/folders/…` can name the
    /// same real directory by different strings. A miss here means a "hermetic" test
    /// quietly writing to the real service.
    @Test func everySpellingOfTheTempDirectoryIsThrowaway() {
        var bases = [
            FileManager.default.temporaryDirectory,
            URL(fileURLWithPath: NSTemporaryDirectory()),
            URL(fileURLWithPath: "/tmp"),
            // `/private/tmp` is the spelling the first implementation of this
            // check missed: Foundation standardizes it down to `/tmp`, but
            // leaves `/private/tmp/<vault>` alone, so the two sides never met.
            URL(fileURLWithPath: "/private/tmp"),
            URL(fileURLWithPath: "/private/var/folders/z5/x/T"),
        ]
        if let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"], !tmpdir.isEmpty {
            bases.append(URL(fileURLWithPath: tmpdir))
        }
        #expect(bases.count >= 5)
        for base in bases {
            let vault = base.appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
            #expect(Home.isThrowawayLocation(vault), "\(vault.path) should be throwaway")
            #expect(
                home(vault: vault).keychainServiceName != Home.canonicalKeychainService,
                "\(vault.path) should not use the canonical service")
        }
    }

    /// Requirement 3: the derivation is stable — same vault, same name, every time.
    /// The name must also be lexical: computing it before and after the vault exists
    /// on disk has to agree, or secrets written early in a session become unreadable
    /// later in it.
    @Test func theSameVaultAlwaysGetsTheSameServiceName() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("kc-stable-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let beforeItExists = home(vault: vault).keychainServiceName
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let afterItExists = home(vault: vault).keychainServiceName
        #expect(beforeItExists == afterItExists)

        // A freshly-built `Home` over the same path agrees, as does an equivalent but
        // non-standardized spelling of that path.
        #expect(home(vault: vault).keychainServiceName == beforeItExists)
        let noisy = vault.appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(vault.lastPathComponent, isDirectory: true)
        #expect(home(vault: noisy).keychainServiceName == beforeItExists)
    }

    /// The cache root is not part of the namespace: only the vault decides it.
    /// Otherwise relocating a disposable cache would strand the secrets.
    @Test func theCacheRootDoesNotAffectTheServiceName() {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("kc-cache-\(UUID().uuidString)", isDirectory: true)
        let one = Home(vaultRoot: vault, cacheRoot: vault.appendingPathComponent("c1"))
        let two = Home(vaultRoot: vault, cacheRoot: vault.appendingPathComponent("c2"))
        #expect(one.keychainServiceName == two.keychainServiceName)
    }

    /// End-to-end: the store `bootstrap` actually builds is namespaced to the
    /// throwaway vault, so writing through it leaves the canonical service alone.
    /// This is the scenario the review described — a test calling `addConnection(...)`
    /// and landing an API key in the developer's real Keychain.
    @Test @MainActor func bootstrapWritesSecretsOutsideTheCanonicalService() {
        let t = TestHome.make("kc-boot")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let id = "kc-probe-\(UUID().uuidString)"
        environment.secrets.setSecret("sk-should-be-isolated", for: id)
        defer { environment.secrets.setSecret(nil, for: id) }

        #expect(environment.secrets.secret(for: id) == "sk-should-be-isolated")
        // The same id read through the canonical service must not see it.
        #expect(KeychainSecretStore(service: Home.canonicalKeychainService).secret(for: id) == nil)
    }
}
