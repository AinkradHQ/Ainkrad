import Foundation

/// A named link surfaced on the app detail page (homepage, changelog,
/// support, …) — see AIN-147.
struct ManifestLink: Codable, Equatable {
    let title: String
    let url: URL
}

/// Discriminates what kind of installable item a `CatalogEntry` represents.
/// Absent on decode (all pre-existing catalog JSON) → defaults to `.plugin`,
/// preserving current behavior for every catalog published before MCP/skill
/// marketplace support existed.
enum CatalogItemKind: String, Codable, Equatable {
    case plugin
    case mcpServer
    case skill
}

/// The fields needed to configure an MCP server from a catalog entry. Only
/// required secret *keys* (names) are declared here — never secret values;
/// actual values are supplied by the user at install time and stored via the
/// existing secrets store.
struct MCPCatalogDescriptor: Codable, Equatable {
    let transport: MCPTransportKind
    let command: String?
    let args: [String]
    let url: URL?
    let envKeys: [String]
    let headerKeys: [String]

    init(
        transport: MCPTransportKind, command: String? = nil, args: [String] = [],
        url: URL? = nil, envKeys: [String] = [], headerKeys: [String] = []
    ) {
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.envKeys = envKeys
        self.headerKeys = headerKeys
    }
}

/// Points at a raw `SKILL.md` asset for a `.skill` catalog entry — a
/// markdown file, not a zip/`dlopen`-loaded plugin bundle. For `.skill`
/// entries, `CatalogEntry.downloadURL`/`sha256` are unused.
struct SkillCatalogDescriptor: Codable, Equatable {
    let contentURL: URL
}

/// One installable app in the hosted catalog (`RemoteCatalogSource`).
///
/// `author`/`longDescription`/`screenshots`/`links` (AIN-147) are additive
/// detail-page metadata. `screenshots`/`links` default to `[]` — both in the
/// memberwise initializer and when decoding a pre-AIN-147 cached catalog
/// JSON that has no such keys — so existing callers/persisted caches are
/// unaffected.
///
/// `kind`/`skill` are additive too: `kind` defaults to `.plugin` and `skill`
/// to `nil` when decoding a pre-existing (kind-less) catalog entry, so
/// existing plugin-only catalogs keep decoding unchanged.
struct CatalogEntry: Equatable, Identifiable, Codable {
    var id: String { appID }
    let appID: String
    let displayName: String
    let icon: String
    let description: String
    let version: String  // release tag_name
    let apiVersion: Int
    let downloadURL: URL  // the .bundle.zip asset
    let sha256: String
    let sourceRepo: String  // "owner/repo"
    let author: String?
    let longDescription: String?
    let screenshots: [URL]
    let links: [ManifestLink]
    /// Defaults to `.plugin` (both here and on decode) so pre-MCP/skill catalog
    /// entries — which have no `kind` field — are unaffected.
    let kind: CatalogItemKind
    /// Only populated for `.mcpServer` entries; `nil` otherwise.
    let mcp: MCPCatalogDescriptor?
    /// Only populated for `.skill` entries; `nil` otherwise.
    let skill: SkillCatalogDescriptor?

    init(
        appID: String, displayName: String, icon: String, description: String, version: String,
        apiVersion: Int, downloadURL: URL, sha256: String, sourceRepo: String,
        author: String? = nil, longDescription: String? = nil,
        screenshots: [URL] = [], links: [ManifestLink] = [],
        kind: CatalogItemKind = .plugin, mcp: MCPCatalogDescriptor? = nil,
        skill: SkillCatalogDescriptor? = nil
    ) {
        self.appID = appID
        self.displayName = displayName
        self.icon = icon
        self.description = description
        self.version = version
        self.apiVersion = apiVersion
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.sourceRepo = sourceRepo
        self.author = author
        self.longDescription = longDescription
        self.screenshots = screenshots
        self.links = links
        self.kind = kind
        self.mcp = mcp
        self.skill = skill
    }

    enum CodingKeys: String, CodingKey {
        case appID, displayName, icon, description, version, apiVersion, downloadURL, sha256, sourceRepo
        case author, longDescription, screenshots, links
        case kind, mcp, skill
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appID = try c.decode(String.self, forKey: .appID)
        displayName = try c.decode(String.self, forKey: .displayName)
        icon = try c.decode(String.self, forKey: .icon)
        description = try c.decode(String.self, forKey: .description)
        version = try c.decode(String.self, forKey: .version)
        apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        downloadURL = try c.decode(URL.self, forKey: .downloadURL)
        sha256 = try c.decode(String.self, forKey: .sha256)
        sourceRepo = try c.decode(String.self, forKey: .sourceRepo)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        longDescription = try c.decodeIfPresent(String.self, forKey: .longDescription)
        screenshots = try c.decodeIfPresent([URL].self, forKey: .screenshots) ?? []
        links = try c.decodeIfPresent([ManifestLink].self, forKey: .links) ?? []
        kind = try c.decodeIfPresent(CatalogItemKind.self, forKey: .kind) ?? .plugin
        mcp = try c.decodeIfPresent(MCPCatalogDescriptor.self, forKey: .mcp)
        skill = try c.decodeIfPresent(SkillCatalogDescriptor.self, forKey: .skill)
    }
}

extension CatalogEntry {
    /// An MCP catalog entry is valid iff it carries a descriptor with a
    /// launch target matching its transport (HTTPS url for httpSSE, command
    /// for stdio). Malformed/incomplete entries are rejected here so a
    /// single bad catalog entry can be skipped (logged) rather than crashing
    /// the whole catalog load.
    var isValidMCPEntry: Bool {
        guard kind == .mcpServer, let mcp else { return false }
        switch mcp.transport {
        case .stdio: return (mcp.command?.isEmpty == false)
        case .httpSSE: return mcp.url?.scheme?.lowercased() == "https"
        // In-process servers are synthesized from installed apps, never catalog-offered;
        // reject malformed entries per the pattern above.
        case .inProcess: return false
        }
    }

    /// True iff this entry is a well-formed `.skill` entry (has a descriptor).
    /// A `.skill`-kind entry missing its descriptor is malformed and should
    /// be treated as skippable rather than fatal, mirroring existing catalog
    /// skip behavior for other malformed entries.
    var isValidSkillEntry: Bool {
        kind == .skill && skill != nil
    }
}
