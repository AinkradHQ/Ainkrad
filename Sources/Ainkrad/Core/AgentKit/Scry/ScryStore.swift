import CoreGraphics
import Foundation
import Observation

/// In-memory projection of the agent's rendered cards, one `ScryModel` per
/// session. Deliberately NOT persisted: the surface is rebuilt by the agent
/// each run, so there is no document to corrupt and nothing on the mutation
/// path touches the disk (the previous implementation wrote the whole document
/// on every mutation, which cost a disk write per pixel of a drag).
///
/// Capped at `cardCap`; adding past the cap evicts the oldest non-pinned card.
@MainActor
@Observable
final class ScryStore {
    static let cardCap = 50

    private var models: [String: ScryModel] = [:]
    private var overridesBySession: [String: [String: ScryRect]] = [:]
    // Drag recency for the floating pass: `overrides` itself is an unordered
    // map, so it records no memory of which card was dragged most recently.
    // The design calls for floating cards to render with the most-recently
    // dragged one last (on top) — this array is that ordering, oldest first.
    private var overrideOrderBySession: [String: [String]] = [:]

    var sessionID: String

    init(sessionID: String = "default") {
        self.sessionID = sessionID
    }

    var model: ScryModel { models[sessionID] ?? ScryModel() }

    /// Rects for cards the user has dragged or resized. A card with an entry
    /// here leaves the auto-layout flow and floats at that rect.
    var overrides: [String: ScryRect] { overridesBySession[sessionID] ?? [:] }

    /// Ids with an override, oldest-dragged first — the order the floating
    /// pass should render in so the most-recently-dragged card ends up last
    /// (on top).
    var overrideOrder: [String] { overrideOrderBySession[sessionID] ?? [] }

    @discardableResult
    func add(_ element: ScryElement) -> String {
        var e = element
        if e.id.isEmpty { e.id = UUID().uuidString }
        var m = model
        m.upsert(e)
        commitEvicting(m)
        return e.id
    }

    func upsert(_ element: ScryElement) {
        var m = model
        m.upsert(element)
        commitEvicting(m)
    }

    func update(id: String, mutate: (inout ScryElement) -> Void) {
        var m = model
        guard var e = m.elements.first(where: { $0.id == id }) else { return }
        mutate(&e)
        m.upsert(e)
        commit(m)
    }

    func remove(id: String) {
        var m = model
        m.remove(id: id)
        commit(m)
        var o = overrides
        o.removeValue(forKey: id)
        overridesBySession[sessionID] = o
        removeFromOverrideOrder(id)
    }

    func setPinned(id: String, _ pinned: Bool) {
        update(id: id) { $0.pinned = pinned }
    }

    func setOverride(id: String, _ rect: ScryRect) {
        var o = overrides
        o[id] = rect
        overridesBySession[sessionID] = o

        var order = overrideOrder
        order.removeAll { $0 == id }
        order.append(id)
        overrideOrderBySession[sessionID] = order
    }

    func clearOverrides() {
        overridesBySession[sessionID] = [:]
        overrideOrderBySession[sessionID] = []
    }

    func clear() {
        models[sessionID] = ScryModel()
        overridesBySession[sessionID] = [:]
        overrideOrderBySession[sessionID] = []
    }

    private func removeFromOverrideOrder(_ id: String) {
        var order = overrideOrder
        order.removeAll { $0 == id }
        overrideOrderBySession[sessionID] = order
    }

    // MARK: - helpers

    private func commit(_ m: ScryModel) {
        models[sessionID] = m
    }

    /// Evicts oldest-first until `m` is within the cap, skipping pinned
    /// cards (if every card is pinned, `m` is left over the cap rather than
    /// discarding something the user asked to keep), then commits — clearing
    /// each evicted card's override so a later re-add under the same id
    /// (agent-supplied ids are stable strings, not UUIDs) never resurrects a
    /// stale user-drag rect for a card that no longer exists.
    private func commitEvicting(_ m: ScryModel) {
        var m = m
        var evictedIDs: [String] = []
        while m.elements.count > Self.cardCap,
              let victim = m.elements.first(where: { !$0.pinned }) {
            m.remove(id: victim.id)
            evictedIDs.append(victim.id)
        }
        commit(m)
        guard !evictedIDs.isEmpty else { return }
        var o = overrides
        for id in evictedIDs { o.removeValue(forKey: id) }
        overridesBySession[sessionID] = o
        var order = overrideOrder
        order.removeAll { evictedIDs.contains($0) }
        overrideOrderBySession[sessionID] = order
    }
}
