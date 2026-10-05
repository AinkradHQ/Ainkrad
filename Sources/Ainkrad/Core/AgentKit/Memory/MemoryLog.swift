import AinkradHostRuntime
import Foundation

/// The reviewable audit trail of every write to the host-internal memory
/// files (USER.md, MEMORY.md, AGENTS.md): who/what triggered the write, what
/// was added, and the prior file snapshot so any entry can be undone.
struct MemoryLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let file: String  // MemoryFile.rawValue
    let provenance: MemoryProvenance
    let addedText: String
    let priorSnapshot: String
}

struct MemoryLogDocument: PersistableDocument {
    static let documentID = "memory-log"
    var entries: [MemoryLogEntry] = []

    init(entries: [MemoryLogEntry] = []) { self.entries = entries }

    // Forward-compatible decoding (same idiom as AgentConfigDocument).
    private enum CodingKeys: String, CodingKey { case entries }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([MemoryLogEntry].self, forKey: .entries) ?? []
    }
}

@MainActor
final class MemoryLogStore {
    private var doc: MemoryLogDocument
    private let persistence: PersistenceStore
    private let memory: MemoryStore

    init(persistence: PersistenceStore, memory: MemoryStore) {
        self.persistence = persistence
        self.memory = memory
        self.doc = persistence.load(MemoryLogDocument.self) ?? MemoryLogDocument()
    }

    func entries() -> [MemoryLogEntry] { doc.entries.sorted { $0.date > $1.date } }

    func record(
        file: MemoryFile, provenance: MemoryProvenance,
        addedText: String, priorSnapshot: String
    ) {
        doc.entries.append(
            MemoryLogEntry(
                id: UUID(), date: Date(), file: file.rawValue,
                provenance: provenance, addedText: addedText, priorSnapshot: priorSnapshot))
        persistence.save(doc)
    }

    func undo(_ id: UUID) {
        guard let entry = doc.entries.first(where: { $0.id == id }),
            let file = MemoryFile(rawValue: entry.file)
        else { return }
        memory.write(entry.priorSnapshot, to: file)
        doc.entries.removeAll { $0.id == id }
        persistence.save(doc)
    }
}
