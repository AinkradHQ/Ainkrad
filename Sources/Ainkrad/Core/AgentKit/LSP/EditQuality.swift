// Sources/Ainkrad/Core/AgentKit/LSP/EditQuality.swift
import Foundation

/// Advisory post-edit LSP integration for `EditFileTool`: after a successful
/// write, best-effort opens/updates the document with the configured
/// language server, applies formatting (writing the formatted text back to
/// disk), and returns a human-readable diagnostics summary.
///
/// Every step is best-effort. There is no server configured for the file's
/// language, the server fails to start, a request throws or times out, or the
/// file can't be re-read — any of these degrade to `nil` ("no advice"). This
/// type NEVER throws and never blocks or fails the edit it rides along with;
/// `EditFileTool` only ever appends what `afterEdit` returns, never inspects
/// it for success/failure.
@MainActor
struct EditQuality {
    /// `nil` when no LSP registry is wired at all (the common case today) —
    /// `afterEdit` short-circuits to `nil` immediately.
    let registry: LSPServerRegistry?

    /// How long to wait for the server to push fresh `publishDiagnostics`
    /// after `didChange`, when none are cached yet. Bounded so a server that
    /// never publishes (or is simply slow) can't stall the tool call.
    private let diagnosticsPollTimeout: TimeInterval

    init(registry: LSPServerRegistry?, diagnosticsPollTimeout: TimeInterval = 0.5) {
        self.registry = registry
        self.diagnosticsPollTimeout = diagnosticsPollTimeout
    }

    /// Runs the advisory pipeline for the file at `path`, which must already
    /// have been written to disk by the caller. Returns a diagnostics summary
    /// string, or `nil` when there's no advice to give (no LSP configured, a
    /// failure at any step, or simply zero diagnostics).
    func afterEdit(path: String) async -> String? {
        guard let registry else { return nil }
        guard let language = registry.language(forFilePath: path) else { return nil }
        guard let originalText = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        let rootURI = "file://" + (path as NSString).deletingLastPathComponent
        let uri = "file://" + path

        guard let client = await registry.client(forFilePath: path, rootURI: rootURI) else { return nil }

        do {
            try await client.didOpen(uri: uri, languageId: language, text: originalText)
        } catch {
            return nil
        }

        var currentText = originalText
        if let edits = try? await client.formatting(uri: uri), !edits.isEmpty {
            let formatted = Self.apply(edits: edits, to: currentText)
            if formatted != currentText {
                if (try? formatted.write(toFile: path, atomically: true, encoding: .utf8)) != nil {
                    currentText = formatted
                    try? await client.didChange(uri: uri, text: currentText)
                }
            }
        }

        var diagnostics = await client.diagnostics(for: uri)
        if diagnostics.isEmpty {
            diagnostics = await Self.pollDiagnostics(client: client, uri: uri, timeout: diagnosticsPollTimeout)
        }
        guard !diagnostics.isEmpty else { return nil }
        return Self.summarize(diagnostics)
    }

    /// Polls cached diagnostics until non-empty or `timeout` elapses — bounded
    /// so an unresponsive/silent server degrades to "no advice" rather than
    /// hanging the edit tool call.
    private static func pollDiagnostics(client: LSPClient, uri: String, timeout: TimeInterval) async -> [LSPDiagnostic]
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let diagnostics = await client.diagnostics(for: uri)
            if !diagnostics.isEmpty { return diagnostics }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await client.diagnostics(for: uri)
    }

    private static func summarize(_ diagnostics: [LSPDiagnostic]) -> String {
        diagnostics.map { diagnostic in
            "\(severityLabel(diagnostic.severity)) \(diagnostic.line + 1):\(diagnostic.character + 1) \(diagnostic.message)"
        }.joined(separator: "\n")
    }

    private static func severityLabel(_ severity: Int) -> String {
        switch severity {
        case 1: return "error"
        case 2: return "warning"
        case 3: return "info"
        case 4: return "hint"
        default: return "note"
        }
    }

    /// Applies a `textDocument/formatting` edit list to `text`, LSP-line-based
    /// (each edit's range spans whole or partial lines, positions in UTF-16
    /// code units per the spec). Edits are applied from the bottom of the
    /// document upward so earlier replacements never invalidate later
    /// (already-processed) ranges. Malformed/out-of-range edits are skipped
    /// individually rather than aborting the whole batch.
    static func apply(edits: [LSPTextEdit], to text: String) -> String {
        guard !edits.isEmpty else { return text }
        var lines = text.components(separatedBy: "\n")
        let ordered = edits.sorted { a, b in
            if a.startLine != b.startLine { return a.startLine > b.startLine }
            return a.startCharacter > b.startCharacter
        }
        for edit in ordered {
            guard edit.startLine >= 0, edit.endLine >= edit.startLine, edit.endLine < lines.count else { continue }
            let startLineText = lines[edit.startLine]
            let endLineText = lines[edit.endLine]
            guard let startIndex = utf16Index(startLineText, edit.startCharacter),
                let endIndex = utf16Index(endLineText, edit.endCharacter)
            else { continue }
            let prefix = String(startLineText[..<startIndex])
            let suffix = String(endLineText[endIndex...])
            let replacement = (prefix + edit.newText + suffix).components(separatedBy: "\n")
            lines.replaceSubrange(edit.startLine...edit.endLine, with: replacement)
        }
        return lines.joined(separator: "\n")
    }

    private static func utf16Index(_ line: String, _ utf16Offset: Int) -> String.Index? {
        let units = line.utf16
        guard utf16Offset >= 0, utf16Offset <= units.count,
            let unitIndex = units.index(units.startIndex, offsetBy: utf16Offset, limitedBy: units.endIndex)
        else {
            return nil
        }
        return unitIndex.samePosition(in: line)
    }
}
