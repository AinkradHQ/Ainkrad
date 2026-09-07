import Foundation
import AinkradAppKit
import AinkradSignal
import AinkradHostRuntime

/// Gives `ainkrad notify` a credential, so the CLI works without the user
/// pairing anything by hand.
///
/// **Minted once, not per launch.** The obvious implementation — mint on every
/// bootstrap and write the file — rotates the token every time the app starts,
/// which invalidates the one already sitting in the user's git hook. The check
/// below is therefore "does the config hold a token the registry still
/// resolves", and only a no on that question mints.
///
/// ## Why the CLI posts as `.host`
///
/// `SignalSource` has three cases and none of them is "a command-line tool".
/// The CLI is Ainkrad's own command-line face, so `.host` is the honest
/// attribution: a `build.failed` from a git hook is the machine telling the
/// user something, exactly like an install failure is.
///
/// The consequence is stated rather than hidden: a leaked CLI token lets its
/// holder post as the host. That is bounded — posting is all a token can do,
/// there is no read path and no action invocation over the socket — and it is
/// why the file is 0600 and why `AINKRAD_SIGNAL_TOKEN` exists, so CI can
/// supply a token without one being written into a workspace.
@MainActor
enum SignalCLIPairing {
    /// `~/Library/Application Support/Ainkrad/cli-signal.json`.
    ///
    /// Beside the Home pointer, in the family's shared directory rather than
    /// under the host's bundle id: the CLI is not the app, and a user who
    /// deletes the app's container should not silently lose a credential their
    /// hooks depend on. `Notify.defaultConfigURL()` derives the same path.
    static func configURL() -> URL {
        AinkradHome.defaultPointerDirectory().appendingPathComponent("cli-signal.json")
    }

    /// Ensures the CLI config holds a token the registry recognises.
    ///
    /// Returns true when it minted a new one. Never throws: failing to pair
    /// the CLI must not affect launch, so a write failure leaves the CLI
    /// unpaired — where it reports `noToken` on stderr and exits 0 — rather
    /// than propagating.
    @discardableResult
    static func ensurePaired(registry: SignalTokenRegistry,
                             configURL url: URL = SignalCLIPairing.configURL()) -> Bool {
        if let existing = readToken(at: url), registry.source(for: existing) != nil {
            return false
        }
        let token = registry.mint(for: .host)
        write(token: token, to: url)
        return true
    }

    private static func readToken(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode([String: String].self, from: data),
              let token = config["token"], !token.isEmpty else { return nil }
        return token
    }

    private static func write(token: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(["token": token]) else { return }
        // Written with 0600 in the ATTRIBUTES, not chmod'ed afterwards: a file
        // that exists world-readable for even an instant has already leaked
        // the credential to anything watching the directory.
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.settings.error("Failed to write \(data.count, privacy: .public) bytes to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: url.path)
    }
}
