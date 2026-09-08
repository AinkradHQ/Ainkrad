import Foundation
import Testing
@testable import Ainkrad

@Suite("ScryElement")
struct ScryElementTests {
    @Test func roundTripsCodable() throws {
        let e = ScryElement(id: "a", kind: .markdown, title: "T", body: "# hi",
                              rect: .defaultCard, z: 3)
        let data = try JSONEncoder().encode(e)
        #expect(try JSONDecoder().decode(ScryElement.self, from: data) == e)
    }

    @Test func unknownKindDecodesToPlaceholder() throws {
        let json = #"{"id":"x","kind":"hologram","body":"","rect":{"x":0,"y":0,"width":10,"height":10},"z":0,"pinned":false}"#
        let e = try JSONDecoder().decode(ScryElement.self, from: Data(json.utf8))
        #expect(e.kind == .unknown)
    }

    @Test func upsertReplacesByID() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: "one", rect: .defaultCard, z: 0))
        m.upsert(ScryElement(id: "a", kind: .text, body: "two", rect: .defaultCard, z: 0))
        #expect(m.elements.count == 1)
        #expect(m.elements.first?.body == "two")
    }

    @Test func orderedSortsByZ() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: "", rect: .defaultCard, z: 5))
        m.upsert(ScryElement(id: "b", kind: .text, body: "", rect: .defaultCard, z: 1))
        #expect(m.ordered.map(\.id) == ["b", "a"])
    }

    @Test func removeDropsElement() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: "", rect: .defaultCard, z: 0))
        m.remove(id: "a")
        #expect(m.elements.isEmpty)
    }

    @Test func documentIDIsStable() {
        #expect(ScryWorkspaceDocument.documentID == "agent-canvas")
    }
}

@Suite("ScrySizeHint")
struct ScrySizeHintTests {
    @Test("each kind has a sensible default size")
    func kindDefaults() {
        #expect(ScrySizeHint.default(for: .status) == .small)
        #expect(ScrySizeHint.default(for: .table) == .full)
        #expect(ScrySizeHint.default(for: .diagram) == .large)
        #expect(ScrySizeHint.default(for: .chart) == .large)
        #expect(ScrySizeHint.default(for: .video) == .large)
        #expect(ScrySizeHint.default(for: .text) == .medium)
        #expect(ScrySizeHint.default(for: .unknown) == .medium)
    }

    @Test("an element with no explicit hint takes its kind's default")
    func derivesFromKind() {
        #expect(ScryElement(id: "a", kind: .table, body: "").sizeHint == .full)
        #expect(ScryElement(id: "b", kind: .status, body: "").sizeHint == .small)
    }

    @Test("an explicit hint wins over the kind default")
    func explicitWins() {
        #expect(ScryElement(id: "c", kind: .table, body: "", sizeHint: .small).sizeHint == .small)
    }

    @Test("an unknown size string decodes to the kind default, never a throw")
    func unknownSizeDecodes() throws {
        let json = #"{"id":"d","kind":"table","body":"x","sizeHint":"gigantic"}"#
        let e = try JSONDecoder().decode(ScryElement.self, from: Data(json.utf8))
        #expect(e.sizeHint == .full)
    }
}
