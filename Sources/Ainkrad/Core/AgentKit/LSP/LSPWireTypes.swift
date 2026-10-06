import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/LSP/LSPWireTypes.swift
import Foundation

/// A single LSP diagnostic, flattened from the wire's `Range` shape (which
/// nests `start`/`end` positions) down to the single `start` position plus
/// severity/message — the shape `LSPClient` (Task 15b) consumes directly.
struct LSPDiagnostic: Equatable {
    let line: Int
    let character: Int
    let severity: Int
    let message: String

    /// Decodes a `textDocument/publishDiagnostics` array element:
    /// `{ range: { start: { line, character } }, severity, message }`.
    /// Missing/malformed fields default to `0`/`""` rather than throwing —
    /// a single bad diagnostic from a flaky server must never crash the host
    /// or drop the rest of the batch.
    static func decode(_ value: JSONValue) -> LSPDiagnostic {
        let start = value["range"]?["start"]
        return LSPDiagnostic(
            line: intValue(start?["line"]) ?? 0,
            character: intValue(start?["character"]) ?? 0,
            severity: intValue(value["severity"]) ?? 0,
            message: value["message"]?.stringValue ?? "")
    }

    private static func intValue(_ value: JSONValue?) -> Int? {
        guard case .number(let n)? = value, n.isFinite else { return nil }
        return Int(exactly: n.rounded())
    }
}

/// A single LSP `TextEdit`: `{ range: { start, end }, newText }`, flattened to
/// four position fields plus the replacement text — what a formatting
/// response (`textDocument/formatting`) resolves to.
struct LSPTextEdit: Equatable {
    let startLine: Int
    let startCharacter: Int
    let endLine: Int
    let endCharacter: Int
    let newText: String

    static func decode(_ value: JSONValue) -> LSPTextEdit {
        let range = value["range"]
        let start = range?["start"]
        let end = range?["end"]
        return LSPTextEdit(
            startLine: intValue(start?["line"]) ?? 0,
            startCharacter: intValue(start?["character"]) ?? 0,
            endLine: intValue(end?["line"]) ?? 0,
            endCharacter: intValue(end?["character"]) ?? 0,
            newText: value["newText"]?.stringValue ?? "")
    }

    private static func intValue(_ value: JSONValue?) -> Int? {
        guard case .number(let n)? = value, n.isFinite else { return nil }
        return Int(exactly: n.rounded())
    }
}

/// Pure JSON-RPC 2.0 message builders for the LSP wire protocol. Distinct from
/// `MCPRPC` only in the methods/params shapes LSP defines — the envelope
/// (`jsonrpc`/`id`/`method`/`params`) is identical, so this mirrors `MCPRPC`'s
/// `request`/`notification` helpers rather than reinventing framing.
enum LSPRPC {
    static func request(id: String, method: String, params: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": .string(id),
            "method": .string(method), "params": params,
        ])
    }

    static func notification(method: String, params: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
    }

    /// `initialize` request params — minimal client capabilities; Task 15b's
    /// `LSPClient` fills in a real `rootUri`/`processId` at call time.
    static func initializeParams(processId: Int, rootUri: String) -> JSONValue {
        .object([
            "processId": .number(Double(processId)),
            "rootUri": .string(rootUri),
            "capabilities": .object([:]),
        ])
    }

    static func initializedNotification() -> JSONValue {
        notification(method: "initialized", params: .object([:]))
    }

    static func didOpenNotification(uri: String, languageId: String, version: Int, text: String) -> JSONValue {
        notification(
            method: "textDocument/didOpen",
            params: .object([
                "textDocument": .object([
                    "uri": .string(uri),
                    "languageId": .string(languageId),
                    "version": .number(Double(version)),
                    "text": .string(text),
                ])
            ]))
    }

    /// Full-document sync (`contentChanges: [{ text }]`) — incremental sync is
    /// out of scope for this slice.
    static func didChangeNotification(uri: String, version: Int, text: String) -> JSONValue {
        notification(
            method: "textDocument/didChange",
            params: .object([
                "textDocument": .object(["uri": .string(uri), "version": .number(Double(version))]),
                "contentChanges": .array([.object(["text": .string(text)])]),
            ]))
    }

    /// Decodes a `textDocument/publishDiagnostics` notification's params into
    /// the flattened `LSPDiagnostic` list.
    static func decodeDiagnostics(_ params: JSONValue) -> [LSPDiagnostic] {
        guard case .array(let items)? = params["diagnostics"] else { return [] }
        return items.map(LSPDiagnostic.decode)
    }

    /// Decodes a `textDocument/formatting` response result (an array of
    /// `TextEdit`, or `null` when no edits are needed).
    static func decodeFormattingResult(_ result: JSONValue) -> [LSPTextEdit] {
        guard case .array(let items) = result else { return [] }
        return items.map(LSPTextEdit.decode)
    }
}
