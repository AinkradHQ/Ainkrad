import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Sandbox/SSHConnectionInfo.swift
import Foundation

/// Minimal remote-host descriptor `SSHBackend` consumes. This IS the
/// host-side Leyline seam: the AinkradSSH plugin (Leyline) is out-of-process
/// and, as of this slice, has no host-side connection code to project from —
/// plugins exchange only strings via the action seam, so a real
/// host↔plugin bridge is out of scope here. Until that bridge exists,
/// backends are wired with `connection: nil` (unavailable, fail-closed).
///
/// `identityPath` is a REFERENCE to a key file on disk, never key material —
/// nothing here should ever hold, encode, or log actual secret bytes. If a
/// future bridge needs to materialize a key from `SecretStore`, it must write
/// it to disk out-of-band and pass only the resulting path here.
struct SSHConnectionInfo: Codable, Equatable, Sendable {
    var host: String
    var user: String
    var port: Int?
    var identityPath: String?
    var remoteWorkingDir: String?
}
