import AinkradHostRuntime
import Foundation

/// Structured, forward-compatible model of user facts (preferences, patterns,
/// style, tooling, conventions). Persisted as `profile.json`; every write is
/// re-projected to the human-editable `USER.md` (the source of truth for
/// manual edits), so the structured form only ever drives targeted recall.
struct UserProfileDocument: PersistableDocument {
    static let documentID = "user-profile"
    var facts: [String: String] = [:]

    init(facts: [String: String] = [:]) { self.facts = facts }

    // Forward-compatible decoding (same idiom as AgentConfigDocument):
    // decodeIfPresent + defaults so later fields never break old payloads.
    private enum CodingKeys: String, CodingKey { case facts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        facts = try c.decodeIfPresent([String: String].self, forKey: .facts) ?? [:]
    }
}

@MainActor
final class UserProfileStore {
    private var doc: UserProfileDocument
    private let persistence: PersistenceStore
    private let memory: MemoryStore

    init(persistence: PersistenceStore, memory: MemoryStore) {
        self.persistence = persistence
        self.memory = memory
        self.doc = persistence.load(UserProfileDocument.self) ?? UserProfileDocument()
    }

    func all() -> [String: String] { doc.facts }

    func set(_ value: String, for key: String) {
        doc.facts[key] = value
        persistence.save(doc)
        project()
    }

    /// Clears a fact entirely, rather than storing an empty string for it.
    /// `project()` writes one `- key: value` line per key in `facts` — if an
    /// emptied field were `set` instead of `remove`d, USER.md would keep a
    /// dangling `- role: ` line that still reads as an (empty) fact. This is a
    /// Settings-pane-only operation: the wizard's `SetupYou.apply` continues
    /// to skip blanks rather than clear, because a field cleared mid-wizard
    /// means "not answered yet", not "delete what was there".
    func remove(_ key: String) {
        doc.facts.removeValue(forKey: key)
        persistence.save(doc)
        project()
    }

    private func project() {
        let body = doc.facts.sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")
        memory.write(body, to: .user)
    }
}
