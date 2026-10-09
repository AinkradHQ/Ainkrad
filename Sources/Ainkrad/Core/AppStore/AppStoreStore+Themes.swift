import AinkradHostRuntime
import SwiftUI

/// The Themes tab's rows: the store's themes and colour schemes, what the
/// store installed, and the themes already on this Mac (bundled or in the
/// Home's themes folder), which show as installed but can never be removed.
extension AppStoreStore {
    static func themeRows(
        entries: [ThemeCatalogEntry], installed: [String: InstalledThemesDocument.Entry],
        themeManager: ThemeManager?
    ) -> [AppStoreRow] {
        let localThemes = themeManager?.themes ?? []
        let localSchemes = ThemeAppearance.allCases.flatMap { themeManager?.colorSchemes(for: $0) ?? [] }
        func isLocal(_ id: String, _ kind: ThemeCatalogEntry.Kind) -> Bool {
            kind == .theme ? localThemes.contains { $0.id == id } : localSchemes.contains { $0.id == id }
        }
        func row(
            id: String, name: String, description: String, kind: ThemeCatalogEntry.Kind,
            catalogVersion: String?, record: InstalledThemesDocument.Entry?, author: String?, themeFiles: Int
        ) -> AppStoreRow {
            let loaded = isLocal(id, kind)
            let status: AppStoreRowStatus
            if let record {
                let newer = catalogVersion.map { PluginVersion.isNewer($0, than: record.version) } ?? false
                status = newer ? .updateAvailable : .installed
            } else {
                status = loaded ? .installed : .available
            }
            var row = AppStoreRow(
                id: id, displayName: name, icon: kind == .theme ? "paintbrush" : "swatchpalette",
                description: description, catalogVersion: catalogVersion, installedVersion: record?.version,
                status: status, isEnabled: true, kind: kind == .theme ? .theme : .colorScheme,
                isManaged: record != nil, author: author)
            guard let themeManager else { return row }
            switch kind {
            case .theme:
                let appearances = themeManager.appearances(ofTheme: id)
                row.appearancesText =
                    loaded && !appearances.isEmpty
                    ? appearances.map(\.title).joined(separator: " · ")
                    : themeFiles > 0 ? "\(themeFiles) appearance\(themeFiles == 1 ? "" : "s")" : nil
                row.isApplied = loaded && themeManager.activeThemeID == id
            case .colorScheme:
                if let scheme = localSchemes.first(where: { $0.id == id }) {
                    row.appearancesText = scheme.appearance.title
                    row.isApplied = themeManager.skin.id == id
                }
                if let skin = themeManager.skin(forScheme: id) {
                    row.swatch = [
                        skin.color(\.background), skin.color(\.accentPrimary), skin.color(\.accentSecondary),
                    ]
                }
            }
            return row
        }

        var rows: [AppStoreRow] = []
        var seen = Set<String>()
        for entry in entries {
            seen.insert(entry.id)
            rows.append(
                row(
                    id: entry.id, name: entry.displayName, description: entry.description, kind: entry.kind,
                    catalogVersion: entry.version, record: installed[entry.id], author: entry.author,
                    themeFiles: entry.files.filter { $0.url.pathExtension == "theme" }.count))
        }
        // Installed, then dropped from the catalog: still removable.
        for (id, record) in installed where !seen.contains(id) {
            seen.insert(id)
            let name = localThemes.first { $0.id == id }?.name ?? localSchemes.first { $0.id == id }?.name ?? id
            rows.append(
                row(
                    id: id, name: name, description: "", kind: record.kind, catalogVersion: nil, record: record,
                    author: nil, themeFiles: 0))
        }
        for theme in localThemes where !seen.contains(theme.id) {
            rows.append(
                row(
                    id: theme.id, name: theme.name, description: "", kind: .theme, catalogVersion: nil, record: nil,
                    author: nil, themeFiles: 0))
        }
        let installedRows = rows.filter { $0.status != .available }.sorted { $0.displayName < $1.displayName }
        let availableRows = rows.filter { $0.status == .available }.sorted { $0.displayName < $1.displayName }
        return installedRows + availableRows
    }

    /// The text a refused theme install shows: the installer's problem lines,
    /// not `AppStoreError.message`'s generic "Invalid app bundle.".
    static func themeFailureText(_ error: Error) -> String {
        switch error as? AppStoreError {
        case .invalidBundle(let problems)?: return problems
        case .download(let reason)?: return "Download failed: \(reason)"
        case let known?: return known.message
        case nil: return String(describing: error)
        }
    }
}

extension ThemeAppearance {
    var title: String { self == .dark ? "Dark" : "Light" }
}
