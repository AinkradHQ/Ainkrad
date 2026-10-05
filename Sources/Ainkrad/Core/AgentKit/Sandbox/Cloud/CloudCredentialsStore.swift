import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Sandbox/Cloud/CloudCredentialsStore.swift
import Foundation

/// Per-provider cloud credentials — Keychain-backed (via `SecretStore`),
/// host-side only. Credentials are NEVER written into a `SandboxProfile`,
/// any other persisted document, or a log; they are addressed by an opaque
/// key and read back through `SecretStore` alone.
///
/// With no credential stored for a provider, that provider is UNCONFIGURED —
/// callers (e.g. `StubCloudSandboxBackend.isAvailable`) must treat this as
/// "cloud unavailable" and fail closed, never falling back to an unsandboxed
/// local run.
@MainActor
final class CloudCredentialsStore {
    private let secrets: SecretStore

    init(secrets: SecretStore) {
        self.secrets = secrets
    }

    private func key(_ provider: CloudProvider) -> String {
        "cloud.\(provider.rawValue).token"
    }

    /// The raw credential value for `provider`, or `nil` if unconfigured.
    func credential(for provider: CloudProvider) -> String? {
        secrets.secret(for: key(provider))
    }

    /// Sets (or, when `value` is `nil`, deletes) the credential for
    /// `provider` — mirrors `SecretStore.setSecret(_:for:)`'s nil-deletes
    /// contract.
    func setCredential(_ value: String?, for provider: CloudProvider) {
        secrets.setSecret(value, for: key(provider))
    }

    /// Whether `provider` has usable credentials. Only checks for existence
    /// of a non-empty value — never returns or logs the secret itself.
    func isConfigured(_ provider: CloudProvider) -> Bool {
        guard let value = credential(for: provider) else { return false }
        return !value.isEmpty
    }
}
