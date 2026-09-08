import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("ScryElementDecoder")
struct ScryElementDecoderTests {
    @Test("decodes the common case")
    func basic() throws {
        let e = try ScryElementDecoder.element(from: .object([
            "id": .string("a"), "kind": .string("table"),
            "title": .string("Rows"), "body": .string("a,b")]))
        #expect(e.id == "a")
        #expect(e.kind == .table)
        #expect(e.title == "Rows")
        #expect(e.sizeHint == .full)      // table's default
    }

    @Test("an explicit size overrides the kind default")
    func explicitSize() throws {
        let e = try ScryElementDecoder.element(from: .object([
            "kind": .string("table"), "body": .string("x"),
            "size": .string("small")]))
        #expect(e.sizeHint == .small)
    }

    @Test("an unrecognised size falls back to the kind default")
    func unknownSize() throws {
        let e = try ScryElementDecoder.element(from: .object([
            "kind": .string("status"), "body": .string("x"),
            "size": .string("enormous")]))
        #expect(e.sizeHint == .small)
    }

    @Test("an unrecognised kind becomes .unknown rather than throwing")
    func unknownKind() throws {
        let e = try ScryElementDecoder.element(from: .object([
            "kind": .string("hologram"), "body": .string("x")]))
        #expect(e.kind == .unknown)
    }

    @Test("a missing id is synthesised")
    func synthesisesID() throws {
        let e = try ScryElementDecoder.element(from: .object([
            "kind": .string("text"), "body": .string("x")]))
        #expect(!e.id.isEmpty)
    }

    @Test("an empty body and no kind is a tool error")
    func emptyIsError() {
        #expect(throws: (any Error).self) {
            try ScryElementDecoder.element(from: .object([:]))
        }
    }

    @Test("merge only touches the fields present in the input")
    func mergeIsPartial() {
        var e = ScryElement(id: "a", kind: .text, title: "Keep", body: "old")
        ScryElementDecoder.merge(.object(["body": .string("new")]), into: &e)
        #expect(e.body == "new")
        #expect(e.title == "Keep")
        #expect(e.kind == .text)
    }
}
