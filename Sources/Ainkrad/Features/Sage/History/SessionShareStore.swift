import AinkradHostRuntime
import Foundation
import Observation

/// Metadata for one on-disk share artifact. The HTML always lives at the
/// deterministic path `<baseDirectory>/<id>/index.html`, so the absolute
/// `filePath` is RECOMPUTED from the store's current base directory + `id` on
/// every load (see `SessionShareStore.init`) — a persisted stale path can never
/// be trusted, which keeps records valid across an Application-Support path
/// change (bundle rename, sandbox relocation).
struct SharedSessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    /// Absolute path to the artifact, resolved against the store's base directory
    /// at load time from `id`. Persisted for convenience but never authoritative.
    var filePath: String
    var fileURL: URL { URL(fileURLWithPath: filePath) }
}

struct SharedSessionsDocument: PersistableDocument {
    static let documentID = "assistant-shares"
    var records: [SharedSessionRecord] = []
    init(records: [SharedSessionRecord] = []) { self.records = records }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([SharedSessionRecord].self, forKey: .records) ?? []
    }
}

/// Writes self-contained HTML share artifacts to disk and tracks their
/// metadata. Private-by-default: only writes on explicit `share(...)`.
@MainActor
@Observable
final class SessionShareStore {
    private(set) var shares: [SharedSessionRecord] = []
    private let persistence: PersistenceStore
    private let baseDirectory: URL
    private let now: () -> Date

    /// `baseDirectory` is required: bootstrap derives it from the resolved `Home`,
    /// tests inject a temp dir. This type never computes a storage path itself.
    init(
        persistence: PersistenceStore,
        baseDirectory: URL,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.baseDirectory = baseDirectory
        self.now = now
        // Recompute every record's absolute path from the CURRENT base directory +
        // id, so a persisted path from a prior (possibly relocated) base is never
        // trusted — the artifact's location is fully determined by its id.
        let loaded = (persistence.load(SharedSessionsDocument.self) ?? SharedSessionsDocument()).records
        shares = loaded.map { record in
            var r = record
            r.filePath = SessionShareStore.artifactURL(base: baseDirectory, id: record.id).path
            return r
        }
    }

    /// The deterministic on-disk location of a share artifact.
    private static func artifactURL(base: URL, id: UUID) -> URL {
        base.appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("index.html")
    }

    @discardableResult
    func share(messages: [AgentMessage], title: String, redactions: [String]) throws -> SharedSessionRecord {
        let id = UUID()
        let fileURL = SessionShareStore.artifactURL(base: baseDirectory, id: id)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let html = SessionShareRenderer.render(messages, title: title, redactions: redactions)
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        let record = SharedSessionRecord(
            id: id, title: title, createdAt: now(),
            filePath: fileURL.path)
        shares.insert(record, at: 0)
        save()
        return record
    }

    func delete(_ id: UUID) {
        guard let idx = shares.firstIndex(where: { $0.id == id }) else { return }
        let dir = baseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        // The record goes regardless: a share whose folder cannot be removed
        // is still one the user asked to forget. The failure is logged.
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            Log.app.error("Sage share delete: could not remove the artifact folder: \(error.localizedDescription)")
        }
        shares.remove(at: idx)
        save()
    }

    private func save() { persistence.save(SharedSessionsDocument(records: shares)) }
}
