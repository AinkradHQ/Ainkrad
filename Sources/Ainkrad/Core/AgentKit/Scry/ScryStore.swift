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

    var sessionID: String

    init(sessionID: String = "default") {
        self.sessionID = sessionID
    }

    var model: ScryModel { models[sessionID] ?? ScryModel() }

    /// Rects for cards the user has dragged or resized. A card with an entry
    /// here leaves the auto-layout flow and floats at that rect.
    var overrides: [String: ScryRect] { overridesBySession[sessionID] ?? [:] }

    @discardableResult
    func add(_ element: ScryElement) -> String {
        var e = element
        if e.id.isEmpty { e.id = UUID().uuidString }
        var m = model
        m.upsert(e)
        commit(evicting(m))
        return e.id
    }

    func upsert(_ element: ScryElement) {
        var m = model
        m.upsert(element)
        commit(evicting(m))
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
    }

    func setPinned(id: String, _ pinned: Bool) {
        update(id: id) { $0.pinned = pinned }
    }

    func setOverride(id: String, _ rect: ScryRect) {
        var o = overrides
        o[id] = rect
        overridesBySession[sessionID] = o
    }

    func clearOverrides() {
        overridesBySession[sessionID] = [:]
    }

    func clear() {
        models[sessionID] = ScryModel()
        overridesBySession[sessionID] = [:]
    }

    // MARK: - helpers

    private func commit(_ m: ScryModel) {
        models[sessionID] = m
    }

    /// Drops oldest-first until the model is within the cap, skipping pinned
    /// cards. If every card is pinned the model is left over the cap rather
    /// than discarding something the user asked to keep.
    private func evicting(_ m: ScryModel) -> ScryModel {
        var m = m
        while m.elements.count > Self.cardCap,
              let victim = m.elements.first(where: { !$0.pinned }) {
            m.remove(id: victim.id)
        }
        return m
    }
}
