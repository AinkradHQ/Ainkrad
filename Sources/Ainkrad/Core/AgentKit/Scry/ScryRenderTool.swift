// Sources/Ainkrad/Core/AgentKit/Scry/ScryRenderTool.swift
import Foundation
import AinkradHostRuntime

/// The agent renders/updates visual output as scry elements. This tool ONLY
/// draws UI from structured data — it executes nothing and touches no files or
/// system state, so it is not a new risk surface (spec §Security). Any tools the
/// agent runs to *produce* the content still pass the normal approval gate.
struct ScryRenderTool: AgentTool {
    let store: ScryStore

    let name = "scry_render"
    let description = """
    Render or update the Live Scry — an auto-arranged surface of cards — instead of a wall of \
    chat text. Use it when output is structured or comparative (tables, diagrams, charts, code, \
    status boards, or several related cards). op: "add" a new element, "update" one in place \
    (stream a table/status as it fills), or "remove" it. kind: text | markdown | table | diagram \
    (mermaid source in body) | chart | image (url/data in body) | code | status | card. \
    Placement is automatic — do not attempt to position cards; use size to say how much room a \
    card needs. Prefer normal chat for short conversational answers.
    """
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "op": .object([
                    "type": .string("string"),
                    "enum": .array([.string("add"), .string("update"), .string("remove")]),
                    "description": .string("Add a new element, update one in place, or remove it."),
                ]),
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Stable element id. Required for update/remove."),
                ]),
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array(ScryElementKind.allCases
                        .filter { $0 != .unknown }.map { .string($0.rawValue) }),
                    "description": .string("Element type (add/update)."),
                ]),
                "title": .object(["type": .string("string")]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string("Content: markdown, mermaid source, CSV/markdown table, code, or image url/data."),
                ]),
                "language": .object(["type": .string("string"),
                                     "description": .string("Language for code elements.")]),
                "size": .object([
                    "type": .string("string"),
                    "enum": .array(ScrySizeHint.allCases.map { .string($0.rawValue) }),
                    "description": .string(
                        "How much room the card wants: small (a chip), medium (default), "
                        + "large (charts, diagrams, video), full (spans the row — tables). "
                        + "Optional; a sensible default is chosen from kind."),
                ]),
            ]),
            "required": .array([.string("op")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        let op = input["op"]?.stringValue ?? "add"
        switch op {
        case "remove":
            guard let id = input["id"]?.stringValue, !id.isEmpty else {
                throw ToolError.message("scry_render remove requires \"id\".")
            }
            store.remove(id: id)
            return ToolResult(content: "Removed scry element \(id).", isError: false)

        case "update":
            guard let id = input["id"]?.stringValue, !id.isEmpty else {
                throw ToolError.message("scry_render update requires \"id\".")
            }
            if var existing = store.model.elements.first(where: { $0.id == id }) {
                ScryElementDecoder.merge(input, into: &existing)
                store.upsert(existing)
            } else {
                // Update of an element that isn't there creates it, so a
                // streaming caller never silently loses a write.
                var created = try ScryElementDecoder.element(from: input)
                created.id = id
                store.upsert(created)
            }
            return ToolResult(content: "Updated scry element \(id).", isError: false)

        default:
            let e = try ScryElementDecoder.element(from: input)
            let id = store.add(e)
            return ToolResult(content: "Rendered scry element \(id) (\(e.kind.rawValue)).",
                              isError: false)
        }
    }

    func isIrreversible(_ input: JSONValue) -> Bool { false }
}
