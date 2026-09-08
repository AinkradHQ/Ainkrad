import Foundation
import AinkradHostRuntime

/// Decodes a `scry_render` tool-call payload into a `ScryElement`.
///
/// Tolerant by design: an unrecognised `kind` becomes `.unknown` and an
/// unrecognised `size` becomes the kind's default, so a newer model emitting a
/// value this build does not know renders a placeholder instead of failing the
/// call. Only a payload with neither kind nor body is an error.
enum ScryElementDecoder {
    static func element(from input: JSONValue) throws -> ScryElement {
        let kindRaw = input["kind"]?.stringValue
        let body = input["body"]?.stringValue ?? ""
        guard kindRaw != nil || !body.isEmpty else {
            throw ToolError.message("scry_render requires \"kind\" and/or \"body\".")
        }
        let kind = kindRaw.flatMap { ScryElementKind(rawValue: $0) } ?? .unknown
        let id = input["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
            ?? UUID().uuidString
        return ScryElement(
            id: id,
            kind: kind,
            title: input["title"]?.stringValue,
            body: body,
            language: input["language"]?.stringValue,
            sizeHint: sizeHint(from: input, kind: kind))
    }

    static func merge(_ input: JSONValue, into e: inout ScryElement) {
        if let k = input["kind"]?.stringValue {
            e.kind = ScryElementKind(rawValue: k) ?? .unknown
        }
        if let t = input["title"]?.stringValue { e.title = t }
        if let b = input["body"]?.stringValue { e.body = b }
        if let l = input["language"]?.stringValue { e.language = l }
        if let s = input["size"]?.stringValue, let hint = ScrySizeHint(rawValue: s) {
            e.sizeHint = hint
        }
    }

    private static func sizeHint(from input: JSONValue,
                                 kind: ScryElementKind) -> ScrySizeHint {
        input["size"]?.stringValue
            .flatMap { ScrySizeHint(rawValue: $0) } ?? .default(for: kind)
    }
}
