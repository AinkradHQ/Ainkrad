import AinkradHostRuntime
import Foundation
import Observation

@MainActor
@Observable
final class SageSessionStore {
    private(set) var sessions: [SavedSession] = []
    private(set) var activeID: UUID?

    private let persistence: PersistenceStore
    private let now: () -> Date

    init(persistence: PersistenceStore, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
        let doc = persistence.load(SageSessionsDocument.self) ?? SageSessionsDocument()
        sessions = doc.sessions.sorted { $0.updatedAt > $1.updatedAt }
        activeID = doc.activeID ?? sessions.first?.id
        if sessions.isEmpty { seedActive() }
    }

    /// Mirrors the live transcript into the active saved session.
    ///
    /// Called from `SageRootView.onChange(of: session.messages)`, which
    /// fires on **every** mutation — including each streamed chunk appended to
    /// the in-flight assistant message. Each call used to re-encode *all*
    /// sessions to JSON and write them to disk synchronously on the main actor,
    /// so a single long reply produced hundreds of full-history rewrites and
    /// the typing animation stuttered in proportion to how much history existed.
    ///
    /// In-memory state still updates synchronously — the sidebar, titles and
    /// `activeMessages` must be correct immediately. Only the *durability* is
    /// coalesced. Structural edits (new/activate/delete) still write straight
    /// through, and `flush()` forces a write at quit.
    func syncActive(messages: [AgentMessage]) {
        guard let id = activeID, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages = messages
        sessions[idx].title = Self.title(from: messages)
        sessions[idx].updatedAt = now()
        resort()
        scheduleSave()
    }

    /// Writes any coalesced change immediately. Call before the process can go
    /// away (app termination) or whenever the transcript must be durable now.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    func startNewSession() {
        let session = SavedSession(createdAt: now(), updatedAt: now())
        sessions.insert(session, at: 0)
        activeID = session.id
        resort()
        save()
    }

    @discardableResult
    func activate(_ id: UUID) -> [AgentMessage] {
        activeID = id
        save()
        return sessions.first(where: { $0.id == id })?.messages ?? []
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        if sessions.isEmpty { seedActive() } else { save() }
    }

    /// Messages of the currently-active session — used at launch to restore the
    /// live AgentSession so the first edit doesn't clobber the saved transcript.
    var activeMessages: [AgentMessage] {
        sessions.first(where: { $0.id == activeID })?.messages ?? []
    }

    func results(for query: String) -> [SavedSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sessions }
        return sessions.filter { s in
            s.title.lowercased().contains(q)
                || s.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    // MARK: - Private

    private func seedActive() {
        let session = SavedSession(createdAt: now(), updatedAt: now())
        sessions = [session]
        activeID = session.id
        save()
    }

    private func resort() { sessions.sort { $0.updatedAt > $1.updatedAt } }

    /// How long a burst of transcript mutations is allowed to coalesce. Short
    /// enough that a crash loses at most a fraction of a second of text; long
    /// enough that an entire streamed reply is one write, not hundreds.
    static let saveCoalescingInterval: Duration = .milliseconds(600)

    private var pendingSave: Task<Void, Never>?

    /// Debounced write: each call replaces the previous pending one, so a burst
    /// of N mutations costs a single encode + disk write instead of N.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveCoalescingInterval)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        persistence.save(SageSessionsDocument(sessions: sessions, activeID: activeID))
    }

    private static func title(from messages: [AgentMessage]) -> String {
        let first =
            messages.first { $0.role == .user }?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty else { return "New chat" }
        return String(first.prefix(40))
    }
}
