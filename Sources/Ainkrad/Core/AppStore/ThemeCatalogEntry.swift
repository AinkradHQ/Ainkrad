import AinkradHostRuntime
import Foundation

/// One entry of the catalog's `themes` array (schema 2): a theme, which may carry the
/// colour schemes its variants name as default, or a standalone colour scheme.
struct ThemeCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case theme, colorScheme
    }

    struct File: Codable, Equatable, Sendable {
        let url: URL
        let sha256: String
    }

    let id: String
    let kind: Kind
    let displayName: String
    let description: String
    let version: String
    let author: String?
    /// The theme-file format the host must understand.
    let format: Int
    let files: [File]
    let screenshots: [URL]?

    /// False when the entry needs a newer theme-file format than this host reads.
    var isCompatible: Bool { format <= ThemeCatalog.supportedFormat }
}

/// Decodes one `themes` element without letting a malformed entry fail the array
/// (and with it the apps): the bad entry is logged and skipped.
struct FailableThemeCatalogEntry: Decodable {
    let entry: ThemeCatalogEntry?

    init(from decoder: Decoder) throws {
        do {
            entry = try ThemeCatalogEntry(from: decoder)
        } catch {
            Log.appStore.error("Skipping malformed theme entry: \(String(describing: error), privacy: .public)")
            entry = nil
        }
    }
}
