import Foundation

enum AppStoreRowStatus: Equatable { case available, installed, updateAvailable }
enum AppStoreRowKind: Equatable { case builtIn, plugin, mcpServer }

/// A plain, SILGen-safe projection of one row in the App Store grid.
struct AppStoreRow: Identifiable, Equatable {
    let id: String  // appID
    let displayName: String
    let icon: String  // SF Symbol
    let description: String
    let catalogVersion: String?  // nil if not in catalog
    let installedVersion: String?  // nil if not installed
    let status: AppStoreRowStatus
    let isEnabled: Bool
    let kind: AppStoreRowKind
    /// True only for plugins the App Store installed (present in the installed
    /// doc) — the ones it can uninstall. Built-ins and dev-sideloaded plugins
    /// (registered but never App Store-installed) are `false`: visible and
    /// toggleable, but not uninstallable via the App Store.
    let isManaged: Bool
    /// From the catalog entry, if any (AIN-148). Used by search.
    let author: String?
    /// Installed or updated while an older copy of its code is loaded: dyld
    /// never unloads a bundle, so the new version runs only after a restart.
    var needsRestart = false
}

extension AppStoreRow {
    /// Drops a single leading `v`/`V` so a catalog `"v1.2"` and a bare
    /// `"1.2"` both normalize to `"1.2"` before we prefix our own `v`.
    static func normalizeVersion(_ v: String) -> String {
        guard let f = v.first, f == "v" || f == "V" else { return v }
        return String(v.dropFirst())
    }

    /// The status-driven version caption shared by the card and detail header.
    var versionLine: String {
        switch status {
        case .available:
            return "v\(AppStoreRow.normalizeVersion(catalogVersion ?? "—"))"
        case .installed:
            return installedVersion.map { "v\(AppStoreRow.normalizeVersion($0)) · installed" } ?? "installed"
        case .updateAvailable:
            return
                "v\(AppStoreRow.normalizeVersion(installedVersion ?? "—")) → v\(AppStoreRow.normalizeVersion(catalogVersion ?? "—"))"
        }
    }
}
