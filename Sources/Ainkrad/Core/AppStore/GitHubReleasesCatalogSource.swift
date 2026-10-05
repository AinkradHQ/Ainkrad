import Foundation

protocol CatalogSource {
    func fetchCatalog() async throws -> [CatalogEntry]
}

/// Assembles catalog entries from the latest release of each configured repo.
/// A repo that fails (network, no release, missing assets) is logged and
/// skipped — one bad repo never aborts the whole catalog.
struct GitHubReleasesCatalogSource: CatalogSource {
    let repositories: [String]  // ["owner/repo", …]
    let http: HTTPClient
    static let manifestAssetName = "ainkrad-plugin.json"

    func fetchCatalog() async throws -> [CatalogEntry] {
        var entries: [CatalogEntry] = []
        for repo in repositories {
            do { entries.append(try await entry(for: repo)) } catch {
                Log.appStore.error(
                    "Catalog: skipped \(repo, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return entries
    }

    private struct SkipRepo: Error {}

    private func entry(for repo: String) async throws -> CatalogEntry {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { throw SkipRepo() }
        let releaseData = try await http.get(url)
        let release = try JSONDecoder().decode(GHRelease.self, from: releaseData)
        guard let manifestAsset = release.assets.first(where: { $0.name == Self.manifestAssetName }),
            let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".bundle.zip") })
        else { throw SkipRepo() }
        let manifest = try JSONDecoder().decode(
            PluginManifest.self, from: try await http.get(manifestAsset.browserDownloadURL))
        return CatalogEntry(
            appID: manifest.id, displayName: manifest.name, icon: manifest.icon,
            description: manifest.description, version: release.tagName, apiVersion: manifest.apiVersion,
            downloadURL: zipAsset.browserDownloadURL, sha256: manifest.sha256, sourceRepo: repo,
            author: manifest.author, longDescription: manifest.longDescription,
            screenshots: manifest.screenshots ?? [], links: manifest.links ?? [])
    }
}
