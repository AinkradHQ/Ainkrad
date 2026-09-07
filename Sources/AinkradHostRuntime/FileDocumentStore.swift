import Foundation
import os

/// A `PersistenceStore` that writes each document as a versioned JSON envelope
/// to `<rootURL>/<documentID>.json`. Writes are atomic (temp file + rename).
/// A file that fails to decode is quarantined (renamed aside) and treated as
/// absent, so a single corrupt document can never crash launch or block the
/// rest of persistence. A write-through cache serves repeat reads.
/// **Thread safety.** Every mutable member is guarded by `lock`. This is not
/// decoration: five call sites reached this store from off the main actor via
/// `nonisolated(unsafe) let persistence` — a real data race on `cache` that
/// Swift 6 was explicitly told to ignore. Those escapes are now gone, and the
/// synchronization lives here, once, where the state is.
///
/// The lock is **recursive** because `load` calls `save` to persist a schema
/// upgrade while already holding it. A plain `NSLock` would deadlock on the
/// first document that migrates.
public final class FileDocumentStore: PersistenceStore, @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSRecursiveLock()
    private var cache: [String: any PersistableDocument] = [:]
    private weak var _syncEngine: SyncEngine?

    /// Optional sync seam; notified after each successful write. Not owned.
    public var syncEngine: SyncEngine? {
        get { lock.withLock { _syncEngine } }
        set { lock.withLock { _syncEngine = newValue } }
    }

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// Drops the in-memory cache. Call after files are written out of band
    /// (e.g. after an import) so subsequent loads read fresh from disk.
    public func clearCache() { lock.withLock { cache.removeAll() } }

    private func fileURL(for id: String) -> URL {
        rootURL.appendingPathComponent("\(id).json")
    }

    private struct SaveEnvelope<Payload: Codable>: Codable {
        let schemaVersion: Int
        let updatedAt: Date
        let payload: Payload
    }

    private struct RawEnvelope: Codable {
        let schemaVersion: Int
        let updatedAt: Date?
        let payload: JSONValue
    }

    public func load<T: PersistableDocument>(_ type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[T.documentID] as? T { return cached }
        let url = fileURL(for: T.documentID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.persistence.error("Failed to read \(T.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let raw = try? PersistenceCoding.decoder.decode(RawEnvelope.self, from: data) else {
            quarantine(url)
            return nil
        }
        var payload = raw.payload
        var version = raw.schemaVersion
        while version < T.currentSchemaVersion {
            guard let migrator = T.migrators.first(where: { $0.fromVersion == version }) else {
                Log.persistence.error("No migrator for \(T.documentID, privacy: .public) v\(version)")
                quarantine(url)
                return nil
            }
            payload = migrator.migrate(payload)
            version += 1
        }
        guard version == T.currentSchemaVersion else {  // stored newer than this build
            quarantine(url)
            return nil
        }
        guard let payloadData = try? PersistenceCoding.encoder.encode(payload),
              let value = try? PersistenceCoding.decoder.decode(T.self, from: payloadData) else {
            quarantine(url)
            return nil
        }
        cache[T.documentID] = value
        if version != raw.schemaVersion { save(value) }  // persist the upgrade
        return value
    }

    public func save<T: PersistableDocument>(_ document: T) {
        let signpost = AinkradSignposts.begin(AinkradSignposts.persistence, "persistence-save")
        defer { AinkradSignposts.end(AinkradSignposts.persistence, "persistence-save", signpost) }
        let envelope = SaveEnvelope(
            schemaVersion: T.currentSchemaVersion, updatedAt: Date(), payload: document)
        guard let data = try? PersistenceCoding.encoder.encode(envelope) else {
            Log.persistence.error("Failed to encode \(T.documentID, privacy: .public)")
            return
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try data.write(to: fileURL(for: T.documentID), options: .atomic)
            cache[T.documentID] = document
            _syncEngine?.documentDidChange(id: T.documentID, data: data)
        } catch {
            Log.persistence.error("Failed to write \(T.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The stored payload JSON for a documentID, unwrapped from the versioned
    /// envelope, without needing the document's Swift type. `nil` if absent or
    /// unreadable. Used by one-time migrations that must move a document whose
    /// type no longer lives in the host.
    public func rawPayloadData(forID id: String) -> Data? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let raw = try? PersistenceCoding.decoder.decode(RawEnvelope.self, from: data),
              let payload = try? PersistenceCoding.encoder.encode(raw.payload) else { return nil }
        return payload
    }

    /// Writes a document's payload as a versioned envelope without needing the
    /// document's Swift type. The mirror image of `rawPayloadData`; used by
    /// one-time migrations moving a document whose type no longer lives in
    /// the host (e.g. settings that have since moved to an App Store
    /// plugin).
    public func saveRawPayload(_ payload: JSONValue, forID id: String, schemaVersion: Int) {
        let envelope = RawEnvelope(schemaVersion: schemaVersion, updatedAt: Date(), payload: payload)
        guard let data = try? PersistenceCoding.encoder.encode(envelope) else {
            Log.persistence.error("Failed to encode raw payload for \(id, privacy: .public)")
            return
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try data.write(to: fileURL(for: id), options: .atomic)
            cache[id] = nil  // no concrete type to cache under; drop any stale entry
            _syncEngine?.documentDidChange(id: id, data: data)
        } catch {
            Log.persistence.error("Failed to write \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func delete<T: PersistableDocument>(_ type: T.Type) {
        lock.lock()
        defer { lock.unlock() }
        cache[T.documentID] = nil
        try? fileManager.removeItem(at: fileURL(for: T.documentID))
    }

    /// Renames a bad file aside so it is out of the way but recoverable.
    private func quarantine(_ url: URL) {
        let destination = url.appendingPathExtension("corrupt-\(UUID().uuidString)")
        do {
            try fileManager.moveItem(at: url, to: destination)
            Log.persistence.error("Quarantined corrupt document \(url.lastPathComponent, privacy: .public)")
        } catch {
            Log.persistence.error("Failed to quarantine corrupt document \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
