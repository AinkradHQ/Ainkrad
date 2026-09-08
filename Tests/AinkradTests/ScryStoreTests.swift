import Foundation
import CoreGraphics
import Testing
@testable import Ainkrad

@Suite("ScryStore")
@MainActor
struct ScryStoreTests {
    @Test("add assigns an id when the element has none")
    func addAssignsID() {
        let s = ScryStore()
        let id = s.add(ScryElement(id: "", kind: .text, body: "hi"))
        #expect(!id.isEmpty)
        #expect(s.model.elements.count == 1)
    }

    @Test("update mutates in place")
    func updateInPlace() {
        let s = ScryStore()
        let id = s.add(ScryElement(id: "e1", kind: .table, body: "row1"))
        s.update(id: id) { $0.body += "\nrow2" }
        #expect(s.model.elements.first?.body == "row1\nrow2")
    }

    @Test("elements keep insertion order, newest last")
    func appendOrder() {
        let s = ScryStore()
        _ = s.add(ScryElement(id: "a", kind: .text, body: ""))
        _ = s.add(ScryElement(id: "b", kind: .text, body: ""))
        #expect(s.model.elements.map(\.id) == ["a", "b"])
    }

    @Test("the cap evicts the oldest element")
    func capEvictsOldest() {
        let s = ScryStore()
        for i in 0..<(ScryStore.cardCap + 3) {
            _ = s.add(ScryElement(id: "e\(i)", kind: .text, body: ""))
        }
        #expect(s.model.elements.count == ScryStore.cardCap)
        #expect(!s.model.elements.contains { $0.id == "e0" })
        #expect(s.model.elements.contains { $0.id == "e\(ScryStore.cardCap + 2)" })
    }

    @Test("a pinned element is never evicted")
    func pinnedSurvivesEviction() {
        let s = ScryStore()
        _ = s.add(ScryElement(id: "keep", kind: .text, body: ""))
        s.setPinned(id: "keep", true)
        for i in 0..<(ScryStore.cardCap + 5) {
            _ = s.add(ScryElement(id: "e\(i)", kind: .text, body: ""))
        }
        #expect(s.model.elements.contains { $0.id == "keep" })
        #expect(s.model.elements.count == ScryStore.cardCap)
    }

    @Test("overrides are recorded per element and clearable")
    func overrides() {
        let s = ScryStore()
        _ = s.add(ScryElement(id: "a", kind: .card, body: ""))
        #expect(s.overrides.isEmpty)
        s.setOverride(id: "a", ScryRect(x: 12, y: 34, width: 300, height: 200))
        #expect(s.overrides["a"]?.x == 12)
        s.clearOverrides()
        #expect(s.overrides.isEmpty)
    }

    @Test("sessions are isolated, including their overrides")
    func sessionIsolation() {
        let s = ScryStore(sessionID: "A")
        _ = s.add(ScryElement(id: "a", kind: .card, body: "in-A"))
        s.setOverride(id: "a", ScryRect(x: 10, y: 20, width: 100, height: 100))

        s.sessionID = "B"
        #expect(s.model.elements.isEmpty)
        #expect(s.overrides.isEmpty)
        _ = s.add(ScryElement(id: "b", kind: .text, body: "in-B"))

        s.sessionID = "A"
        #expect(s.model.elements.map(\.id) == ["a"])
        #expect(s.overrides["a"]?.x == 10)
    }

    @Test("clear empties the active session only")
    func clearIsPerSession() {
        let s = ScryStore(sessionID: "A")
        _ = s.add(ScryElement(id: "a", kind: .text, body: ""))
        s.sessionID = "B"
        _ = s.add(ScryElement(id: "b", kind: .text, body: ""))
        s.clear()
        #expect(s.model.elements.isEmpty)
        s.sessionID = "A"
        #expect(s.model.elements.count == 1)
    }

    @Test("an all-pinned model is left over the cap")
    func allPinnedLeftOverCap() {
        let s = ScryStore()
        for i in 0..<(ScryStore.cardCap + 5) {
            _ = s.add(ScryElement(id: "e\(i)", kind: .text, body: "", pinned: true))
        }
        #expect(s.model.elements.count == ScryStore.cardCap + 5)
        #expect(s.model.elements.allSatisfy { $0.pinned })
    }

    @Test("a drag records an override without mutating the element")
    func dragRecordsOverrideOnly() {
        let s = ScryStore()
        let id = s.add(ScryElement(id: "a", kind: .card, body: "x"))
        let before = s.model.elements.first!
        s.setOverride(id: id, ScryRect(x: 200, y: 300, width: 400, height: 250))
        #expect(s.model.elements.first! == before)   // element untouched
        #expect(s.overrides[id]?.x == 200)
    }

    @Test("remove drops the element's override entry")
    func removeDropsOverride() {
        let s = ScryStore()
        _ = s.add(ScryElement(id: "a", kind: .card, body: ""))
        s.setOverride(id: "a", ScryRect(x: 1, y: 2, width: 3, height: 4))
        #expect(s.overrides["a"] != nil)
        s.remove(id: "a")
        #expect(s.overrides["a"] == nil)
    }

    @Test("eviction by the cap drops the evicted card's override entry")
    func evictionDropsOverride() {
        let s = ScryStore()
        let firstID = "e0"
        _ = s.add(ScryElement(id: firstID, kind: .card, body: ""))
        s.setOverride(id: firstID, ScryRect(x: 1, y: 2, width: 3, height: 4))
        #expect(s.overrides[firstID] != nil)

        for i in 1..<(ScryStore.cardCap + 1) {
            _ = s.add(ScryElement(id: "e\(i)", kind: .text, body: ""))
        }
        #expect(!s.model.elements.contains { $0.id == firstID })
        #expect(s.overrides[firstID] == nil)

        // Re-adding under the same (agent-supplied, stable) id must not
        // resurrect the stale override.
        _ = s.add(ScryElement(id: firstID, kind: .card, body: "back"))
        #expect(s.overrides[firstID] == nil)
    }
}
