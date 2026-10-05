import AinkradAppKit
import Foundation

/// Shared plugin metadata validation, used by both the load-time `PluginLoader`
/// and the install-time `PluginInstaller` so the two cannot drift.
public enum PluginValidator {
    public static func isValidAppID(_ id: String) -> Bool {
        PluginValidation.isValidAppID(id)
    }

    /// Validates app-id safety, executable presence, and API-version
    /// compatibility (NOT signature — separate policy — and NOT `Bundle.load()`).
    /// Delegates to `AinkradAppKit.PluginValidation` so the host, CLI, and Dev
    /// Host share one definition and cannot drift.
    public static func validate(
        _ metadata: PluginBundleMetadata,
        infoDictionary: [String: Any],
        minSupportedAPIVersion: Int
    ) -> Result<Void, PluginRejection> {
        PluginValidation.validate(
            metadata: metadata,
            infoDictionary: infoDictionary,
            minSupported: minSupportedAPIVersion,
            current: AinkradAppKit.apiVersion
        )
        .mapError { PluginRejection(reason: $0.reason) }
    }
}
