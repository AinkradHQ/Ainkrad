import Foundation
import Testing
@testable import Ainkrad

@Suite("ScryElement")
struct ScryElementTests {
    @Test func roundTripsCodable() throws {
        let e = ScryElement(id: "a", kind: .markdown, title: "T", body: "# hi")
        let data = try JSONEncoder().encode(e)
        #expect(try JSONDecoder().decode(ScryElement.self, from: data) == e)
    }

    @Test func unknownKindDecodesToPlaceholder() throws {
        let json = #"{"id":"x","kind":"hologram","body":"","pinned":false}"#
        let e = try JSONDecoder().decode(ScryElement.self, from: Data(json.utf8))
        #expect(e.kind == .unknown)
    }

    @Test func upsertReplacesByID() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: "one"))
        m.upsert(ScryElement(id: "a", kind: .text, body: "two"))
        #expect(m.elements.count == 1)
        #expect(m.elements.first?.body == "two")
    }

    @Test func elementsPreserveAppendOrder() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: ""))
        m.upsert(ScryElement(id: "b", kind: .text, body: ""))
        #expect(m.elements.map(\.id) == ["a", "b"])
    }

    /// Array position is the entire recency mechanism now that `z` is gone —
    /// re-upserting an existing id must replace it IN PLACE, not move it to
    /// the end. An implementation that appended on every upsert instead would
    /// silently reorder every streaming table update, with nothing failing.
    @Test func reUpsertReplacesInPlaceRatherThanReordering() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: "1"))
        m.upsert(ScryElement(id: "b", kind: .text, body: "1"))
        m.upsert(ScryElement(id: "a", kind: .text, body: "2"))
        #expect(m.elements.map(\.id) == ["a", "b"])
        #expect(m.elements.first(where: { $0.id == "a" })?.body == "2")
    }

    @Test func removeDropsElement() {
        var m = ScryModel()
        m.upsert(ScryElement(id: "a", kind: .text, body: ""))
        m.remove(id: "a")
        #expect(m.elements.isEmpty)
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

@Suite("ScryElement has no stored geometry")
struct ScryElementGeometryTests {
    @Test("geometry is not part of the encoded element")
    func noGeometryEncoded() throws {
        let e = ScryElement(id: "a", kind: .text, body: "hello")
        let json = try JSONEncoder().encode(e)
        let text = String(decoding: json, as: UTF8.self)
        for banned in ["\"rect\"", "\"z\"", "\"x\"", "\"y\"", "\"width\"", "\"height\""] {
            #expect(!text.contains(banned), "element still encodes \(banned)")
        }
    }

    @Test("an old document with rect and z still decodes")
    func legacyDecodes() throws {
        let json = #"{"id":"a","kind":"text","body":"x","z":4,"rect":{"x":1,"y":2,"width":3,"height":4}}"#
        let e = try JSONDecoder().decode(ScryElement.self, from: Data(json.utf8))
        #expect(e.id == "a")
        #expect(e.sizeHint == .medium)
    }
}
