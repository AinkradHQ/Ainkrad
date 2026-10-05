import AinkradHostRuntime
import Foundation

/// A portable bundle of the user's documents. Secrets are intentionally not
/// included — they live in the Keychain, never in the documents directory.
struct UserDataExport: Codable {
    var exportSchemaVersion: Int
    var documents: [String: JSONValue]
}

enum UserDataPorterError: Error {
    case unsupportedVersion
}

/// Exports every JSON document in the store's directory into a single bundle,
/// and imports one back. Operates on raw files so it is agnostic to document
/// types. After importing into a live store, call `FileDocumentStore.clearCache()`
/// (or relaunch) so cached reads pick up the new files.
final class UserDataPorter {
    static let exportSchemaVersion = 1

    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func export() throws -> Data {
        let entries =
            (try? fileManager.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: nil)) ?? []
        var documents: [String: JSONValue] = [:]
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let value = try? PersistenceCoding.decoder.decode(JSONValue.self, from: data)
            else {
                continue  // skip anything unreadable rather than fail the whole export
            }
            documents[url.deletingPathExtension().lastPathComponent] = value
        }
        let export = UserDataExport(
            exportSchemaVersion: Self.exportSchemaVersion, documents: documents)
        return try PersistenceCoding.encoder.encode(export)
    }

    func importData(_ data: Data) throws {
        let export = try PersistenceCoding.decoder.decode(UserDataExport.self, from: data)
        guard export.exportSchemaVersion == Self.exportSchemaVersion else {
            throw UserDataPorterError.unsupportedVersion
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (id, value) in export.documents {
            let payload = try PersistenceCoding.encoder.encode(value)
            try payload.write(to: rootURL.appendingPathComponent("\(id).json"), options: .atomic)
        }
    }
}
