import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Sandbox/SSHConnectionResolver.swift
import Foundation

/// Why a connection id did not become a connection. Carries the user-facing
/// text and nothing else — the callers have no reason to branch on the cause,
/// they only ever refuse and say why.
struct SSHConnectionResolutionFailure: Error, Equatable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// Turns a saved-connection id into the `SSHConnectionInfo` `SSHBackend` needs,
/// or into a reason the run cannot happen.
///
/// A `Result` rather than an optional on purpose: a nil would collapse four
/// very different situations — Leyline not installed, an id that names nothing,
/// a password-only connection, a passphrase-protected key — into one "couldn't"
/// that the user cannot act on. The failure text is what reaches them, so each
/// of those four says what to do next.
///
/// Injected as a closure rather than reached through the action hub directly,
/// the way `AppServerActivator` takes closures: the fail-closed behaviour is
/// the most important property in this file, and it has to be testable without
/// a live plugin, a live hub, or a live remote machine.
typealias SSHConnectionResolver =
    @Sendable (String) async -> Result<SSHConnectionInfo, SSHConnectionResolutionFailure>

/// The concrete, Leyline-backed resolver — the host end of
/// `leyline.resolve_connection`.
///
/// This is a **host-only action, never an MCP tool**, and the asymmetry is
/// deliberate on both sides: the reply carries `identityPath`, a filesystem
/// path to a plaintext private key, so a model that could call it could read
/// the key with any file-reading tool it has. `AgentActionRegistryHub.invoke`
/// is reachable only from host code — which is exactly what this is.
enum LeylineConnectionResolver {
    /// The action id Leyline registers. Matches `LeylineConnectionBridge.actionID`.
    static let actionID = "leyline.resolve_connection"

    /// Builds a resolver over `hub`. Returns a `.failure` in every path that
    /// isn't a fully resolved connection — there is no "close enough" here,
    /// because the caller's only alternative to a connection is refusing to run.
    static func make(hub: AgentActionRegistryHub) -> SSHConnectionResolver {
        { identifier in
            let payload = requestJSON(connection: identifier)
            // nil means no handler is registered for the id: Leyline isn't
            // installed, or isn't loaded in this session.
            guard let reply = await hub.invoke(actionID: actionID, input: payload) else {
                return .failure(
                    SSHConnectionResolutionFailure(
                        "No SSH connection provider is available — the Leyline app is not "
                            + "installed or did not load. Install Leyline and add the connection "
                            + "there, then run this again."))
            }
            // Leyline's own refusals are already specific and actionable
            // (unknown id, password-only, passphrase-protected key), so they
            // are passed through verbatim rather than flattened into a generic
            // message here.
            if reply.isError { return .failure(SSHConnectionResolutionFailure(reply.text)) }
            guard
                let info = try? JSONDecoder()
                    .decode(SSHConnectionInfo.self, from: Data(reply.text.utf8))
            else {
                return .failure(
                    SSHConnectionResolutionFailure(
                        "The SSH connection provider returned something this version of Ainkrad "
                            + "could not read. Update Leyline and Ainkrad to matching versions."))
            }
            return .success(info)
        }
    }

    /// `{"connection": "<id>"}`, encoded rather than interpolated so an id with
    /// a quote in it cannot forge a second field.
    private static func requestJSON(connection: String) -> String {
        guard
            let data =
                try? JSONSerialization
                .data(withJSONObject: ["connection": connection])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
