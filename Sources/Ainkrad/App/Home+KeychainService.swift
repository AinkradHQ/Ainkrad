import AinkradAppKit
import CryptoKit
import Foundation

/// Where the Keychain service name comes from.
///
/// Secrets never live in the vault — they live in the Keychain, which sits outside
/// the Home entirely. But the Keychain still needs a *namespace*, and that namespace
/// used to be `Bundle.main.bundleIdentifier`: one global service shared by every
/// process using this bundle, the test runner included. A test bootstrapping onto a
/// throwaway vault would read and write the developer's real API keys.
///
/// So the service name is a pure function of the vault location. There is no
/// "am I a test" branch — a vault in a throwaway location simply yields a throwaway
/// namespace, which makes test isolation a property of the derivation rather than
/// something a caller has to remember to ask for.
///
/// **The direction of the question matters.** This deliberately asks "is the vault in
/// a throwaway location?" and not "is the vault at a location I recognize?". Secrets
/// are global to the user, and the wizard lets them put their vault anywhere, so the
/// set of legitimate vault paths is unbounded — no allowlist of known-good roots can
/// ever be complete. An allowlist fails *dangerous*: an unrecognized path would
/// silently get its own namespace, making every previously saved API key unreachable
/// with no error surfaced. Asking the opposite question gives a deny-list of exactly
/// one location, which fails *safe* — anything unrecognized resolves to the canonical
/// service and the user's keys keep working.
extension Home {
    /// The app's canonical Keychain service — the exact string every release has
    /// stored secrets under, and the answer for every real vault, wherever the user
    /// chose to put it.
    static var canonicalKeychainService: String {
        Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
    }

    /// The Keychain service every secret for this Home is namespaced under.
    ///
    /// The *decision* (throwaway or not) resolves symlinks, because `/tmp`,
    /// `/private/tmp`, `$TMPDIR` and `/var/folders/…` are several spellings of the
    /// same few real directories and a purely textual comparison would miss most of
    /// them. The *name*, once that decision is made, is derived lexically from
    /// `standardizedFileURL.path` with no filesystem access, so it cannot change
    /// between two calls in one session — a name that shifted once the vault appeared
    /// on disk would strand every secret written before that point.
    var keychainServiceName: String {
        guard Home.isThrowawayLocation(vaultRoot) else { return Home.canonicalKeychainService }
        // Hashed rather than path-appended: Keychain service names are opaque
        // strings, and a vault path can be long, non-ASCII, or something the user
        // would not want surfaced in a Keychain Access listing.
        let digest = SHA256.hash(data: Data(vaultRoot.standardizedFileURL.path.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(Home.canonicalKeychainService).vault.\(digest)"
    }

    /// True when this Home is a throwaway — the first-run wizard's provisional
    /// Home, or a test's `TestHome`.
    ///
    /// Named for the invariant it exists to state: **no secret may be written
    /// while this is true**, because `keychainServiceName` above namespaces a
    /// provisional Home's secrets under a hashed throwaway service that the
    /// environment rebuilt against the user's real vault never reads. A
    /// credential entered before adoption is accepted, stored, and then
    /// silently unreachable. See `AinkradHostApp.install(_:into:)`.
    ///
    /// This is exactly the predicate `keychainServiceName` branches on, exposed
    /// under a name a caller can assert against rather than left implicit in
    /// the derivation.
    var isProvisional: Bool { Home.isThrowawayLocation(vaultRoot) }

    /// True when `url` sits inside a system temporary directory — the one place no
    /// genuine user vault ever is, and the place every test vault is.
    static func isThrowawayLocation(_ url: URL) -> Bool {
        let spellings = spellings(of: url)
        return throwawayBases.contains { base in
            spellings.contains { isDescendant($0, of: base) }
        }
    }

    /// Every spelling of "the temp directory" this process might encounter. macOS
    /// hands out a per-user `/var/folders/…` path via `temporaryDirectory` and
    /// `TMPDIR`, while `/tmp` and `/var` are symlinks into `/private`.
    private static var throwawayBases: Set<String> {
        var urls = [
            FileManager.default.temporaryDirectory,
            URL(fileURLWithPath: NSTemporaryDirectory()),
            URL(fileURLWithPath: "/tmp"),
            URL(fileURLWithPath: "/var/folders"),
        ]
        if let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"], !tmpdir.isEmpty {
            urls.append(URL(fileURLWithPath: tmpdir))
        }
        return urls.reduce(into: Set<String>()) { $0.formUnion(spellings(of: $1)) }
    }

    /// Every string that can name the same directory as `url`.
    ///
    /// Two normalizations, and they are not interchangeable. `standardizedFileURL`
    /// and `resolvingSymlinksInPath` disagree about the `/private` prefix depending
    /// on how long the path is and whether the leaf exists: `/private/tmp`
    /// standardizes *down* to `/tmp`, while `/private/tmp/some-vault` (leaf absent)
    /// stays as written. Comparing one normalization against the other therefore
    /// misses real matches — that exact asymmetry let a vault under `/private/tmp`
    /// take the production branch, which is why `/private` is now folded explicitly
    /// in both directions rather than being left to Foundation.
    private static func spellings(of url: URL) -> Set<String> {
        var out: Set<String> = []
        for path in [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path] {
            out.insert(path)
            if path.hasPrefix("/private/") {
                out.insert(String(path.dropFirst("/private".count)))
            } else {
                out.insert("/private" + path)
            }
        }
        return out
    }

    /// Component-wise prefix test, so `/tmpfoo` is never read as living in `/tmp`.
    private static func isDescendant(_ path: String, of base: String) -> Bool {
        guard path != base else { return true }
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}
