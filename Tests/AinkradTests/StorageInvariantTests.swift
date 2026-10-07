import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// The three invariants the storage-root refactor exists to establish. Each is
/// written to fail loudly the moment a future change re-introduces the drift it
/// was meant to remove.
@Suite("Storage invariants")
@MainActor
struct StorageInvariantTests {

    // MARK: - Invariant 1: the cache is disposable

    /// The split rule (*authored or irreplaceable → vault; derivable → cache*)
    /// as an executable assertion: deleting `cacheRoot` wholesale must lose
    /// nothing.
    ///
    /// Stronger than "one setting survives": it seeds an authored artifact into
    /// every `SharedDomain`, snapshots the entire vault tree, nukes the cache,
    /// re-bootstraps, and asserts every path that existed before still exists
    /// with byte-identical contents.
    @Test func deletingTheEntireCacheLosesNothing() throws {
        let t = TestHome.make("inv")
        defer { t.cleanup() }
        let fm = FileManager.default

        let first = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        first.themeManager.setFontScale(.large)
        let expectedScale = first.themeManager.uiFontScale

        // Authored content in every shared domain — the things a user would be
        // entitled to be furious about losing.
        var seeded: [URL: Data] = [:]
        for domain in SharedDomain.allCases {
            let dir = t.home.shared(domain)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("authored-\(domain.rawValue).txt")
            let body = Data("authored content for \(domain.rawValue)".utf8)
            try body.write(to: file)
            seeded[file] = body
        }

        let vaultBefore = Self.snapshot(of: t.home.vaultRoot)
        #expect(!vaultBefore.isEmpty, "the vault should not be empty after bootstrap")

        try fm.removeItem(at: t.home.cacheRoot)
        #expect(!fm.fileExists(atPath: t.home.cacheRoot.path))

        let second = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        // 1. The settings document survives.
        #expect(second.themeManager.uiFontScale == expectedScale)
        #expect(fm.fileExists(atPath: t.home.shared(.config).path))

        // 2. Every authored file survives, byte for byte.
        for (file, body) in seeded {
            let read = try? Data(contentsOf: file)
            #expect(read == body, "authored file lost or altered: \(file.lastPathComponent)")
        }

        // 3. Nothing at all vanished from the vault.
        let vaultAfter = Self.snapshot(of: t.home.vaultRoot)
        let lost = vaultBefore.subtracting(vaultAfter).sorted()
        #expect(lost.isEmpty, "deleting the cache lost these vault paths: \(lost)")
    }

    /// The other half of invariant 1, stated positively: only known-derivable
    /// data is allowed to land under `cacheRoot`.
    ///
    /// This is the test that actually catches the regression. Deleting the cache
    /// only "loses nothing" for as long as nobody writes anything authored there,
    /// and a round-trip test cannot see content that does not yet exist. So the
    /// allowlist is deliberately narrow: adding a new cache directory *must*
    /// break this test, forcing the author to state that the new data is
    /// reconstructible.
    @Test func onlyDerivableDataLivesUnderTheCacheRoot() throws {
        let t = TestHome.make("inv-cache")
        defer { t.cleanup() }

        _ = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let fm = FileManager.default

        // Anti-vacuity: `contentsOfDirectory` on a missing root returns nothing,
        // so without this the whole check would silently pass while inspecting
        // an empty list. Same guard as the `Sources/` scan below.
        var isDirectory: ObjCBool = false
        #expect(
            fm.fileExists(atPath: t.home.cacheRoot.path, isDirectory: &isDirectory)
                && isDirectory.boolValue,
            "cacheRoot missing after bootstrap — this guard is not scanning anything")

        // Every entry here is regenerated from scratch on next launch:
        // - Plugins / DevPlugins: installed bundles, re-installable from source.
        // - Apps: per-app machine-local scratch (`Home.cache(app:)`).
        // - Checkpoints: undo history for a session, expressly ephemeral.
        let derivable: Set<String> = ["Plugins", "DevPlugins", "Apps", "Checkpoints"]

        let topLevel = try fm.contentsOfDirectory(
            at: t.home.cacheRoot,
            includingPropertiesForKeys: nil)
        let unexpected = topLevel.map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") && !derivable.contains($0) }
            .sorted()

        #expect(
            unexpected.isEmpty,
            """
            unclassified data under cacheRoot: \(unexpected). \
            Either move it to the vault (if authored or irreplaceable) or add it \
            to `derivable` with a note saying how it is regenerated.
            """)

        // A depth-1 check alone does not establish the invariant: authored data
        // written to `cacheRoot/Plugins/notes.md` or `cacheRoot/Apps/<id>/x.md`
        // is invisible to it, because the *parent* is allowlisted. So walk the
        // whole tree, and assert the property that actually holds for a bare
        // bootstrap: it produces the cache *skeleton* and nothing else. Derived
        // data is by definition derived *from* something, and a bootstrap with
        // no user activity has nothing to derive from — so any regular file
        // here is content the app wrote unprompted, which has to be justified.
        //
        // Bound: the walk stops after `budget` entries and fails loudly rather
        // than truncating silently, so a large legitimately-derived tree becomes
        // a visible prompt to revisit this test rather than a hole in it. A bare
        // bootstrap produces single digits, so 5000 is orders of magnitude of
        // headroom while still capping the runtime.
        let budget = 5_000
        var files: [String] = []
        var seen = 0
        let prefix = t.home.cacheRoot.standardizedFileURL.path
        let walker = fm.enumerator(
            at: t.home.cacheRoot,
            includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in walker {
            seen += 1
            if seen > budget { break }
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            guard
                (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                    .isRegularFile == true
            else { continue }
            let path = url.standardizedFileURL.path
            files.append(path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path)
        }

        #expect(
            seen <= budget,
            """
            cacheRoot has more than \(budget) entries after a bare bootstrap. \
            The walk was truncated, so this guard is no longer complete — \
            revisit it rather than raising the bound blindly.
            """)
        #expect(
            files.sorted().isEmpty,
            """
            a bare bootstrap wrote files into cacheRoot: \(files.sorted()). \
            Nothing authored or irreplaceable may live under cacheRoot — if \
            these are genuinely derivable, say here what regenerates them.
            """)
    }

    // MARK: - Invariant 2: no subsystem computes its own storage path

    /// This is what keeps the six-way drift from growing back: the refactor
    /// deleted six `defaultRoot()`-style functions, and nothing may reintroduce
    /// an alternative path computation.
    @Test func noSourceFileComputesAnApplicationSupportPath() throws {
        let sources = Self.repoRoot.appendingPathComponent("Sources", isDirectory: true)

        // Fail loudly rather than vacuously if the repo layout ever moves: an
        // enumerator over a missing directory would otherwise find no offenders
        // and pass forever.
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory)
                && isDirectory.boolValue,
            "Sources/ not found at \(sources.path) — this guard is not scanning anything")

        // The migration reader is the one legitimate exception: it must be able
        // to find the pre-Home tree in order to move it into the vault.
        let allowed = ["VaultMigration.swift"]

        // Scope, stated plainly: this matches the token `applicationSupportDirectory`
        // and nothing else. A file assembling `~/Library/Application Support/…`
        // from a string literal or `NSHomeDirectory()` would evade it. That is a
        // narrower guard than the test's name suggests, and deliberately so —
        // the token is what the six deleted `defaultRoot()` functions all used,
        // so it is the precise signature of the drift being prevented. There is
        // no live offender of the broader kind today (the other
        // "Application Support" occurrences in `Sources/` are all comments).
        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !allowed.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("applicationSupportDirectory") {
                offenders.append(url.lastPathComponent)
            }
        }

        #expect(
            offenders.isEmpty,
            "these compute their own storage path: \(offenders.sorted())")
    }

    // MARK: - Invariant 3: the test suite never touches the real Keychain

    /// `Home.keychainServiceName` asks "is this vault in a throwaway location?",
    /// which fails *safe* — an unrecognised path resolves to the canonical
    /// service so a real user keeps their API keys. The cost is that it fails
    /// *silently* in the test direction: a test whose vault the temp check does
    /// not recognise would write to the developer's real Keychain and still
    /// pass.
    ///
    /// This closes that gap by testing the suite's real factory output, not a
    /// hand-built lookalike path — so it fails if `TestHome` is ever changed to
    /// build vaults outside the temp tree.
    @Test func testHomesNeverResolveToTheCanonicalKeychainService() {
        let canonical = Home.canonicalKeychainService

        var made: [(home: Home, cleanup: () -> Void)] = []
        defer { made.forEach { $0.cleanup() } }
        for label in ["kc", "kc-2", "a b", "unicode-é"] {
            let t = TestHome.make(label)
            made.append((t.home, t.cleanup))
        }

        for (home, _) in made {
            #expect(
                home.keychainServiceName != canonical,
                """
                TestHome.make built a vault at \(home.vaultRoot.path) whose Keychain \
                service is the canonical one — this suite would read and write the \
                developer's real API keys.
                """)
            #expect(
                home.keychainServiceName.hasPrefix(canonical + ".vault."),
                "unexpected service name: \(home.keychainServiceName)")
            #expect(
                Home.isThrowawayLocation(home.vaultRoot),
                "TestHome vault is not in a throwaway location: \(home.vaultRoot.path)")
        }

        // The guard is only meaningful if the canonical branch is reachable at
        // all — otherwise the assertions above could not fail.
        //
        // Coupling, acknowledged: this assumes `NSHomeDirectory()` is not itself
        // inside a temp directory. Under a redirected `HOME` it would fail — but
        // it fails *loudly*, with the service name in the message, which is the
        // acceptable direction for a sanity check to break.
        let real = Home(
            vaultRoot: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Ainkrad", isDirectory: true),
            cacheRoot: URL(fileURLWithPath: NSHomeDirectory()))
        #expect(real.keychainServiceName == canonical)
    }

    // MARK: - Helpers

    /// The repo root, derived from this file's compile-time location
    /// (`Tests/AinkradTests/StorageInvariantTests.swift`).
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AinkradTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    /// Every path under `root`, relative to it.
    private static func snapshot(of root: URL) -> Set<String> {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var out: Set<String> = []
        let prefix = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            out.insert(path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path)
        }
        return out
    }
}
