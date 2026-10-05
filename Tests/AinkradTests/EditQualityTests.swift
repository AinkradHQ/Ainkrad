import AinkradHostRuntime
// Tests/AinkradTests/EditQualityTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("EditQuality / EditFileTool degradation")
@MainActor
struct EditQualityTests {
    /// Computes a path in a fresh temp directory WITHOUT creating the file —
    /// tests exercise `edit_file`'s create-on-empty-`old_string` path, so a
    /// pre-existing file would make that call throw "already exists".
    private func tempFile(named name: String = "a.swift") -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("eq-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        return (dir, url.path)
    }

    private func seeded(_ doc: LSPServersDocument) -> PersistenceStore {
        let p = InMemoryPersistenceStore()
        p.save(doc)
        return p
    }

    // MARK: - Never-block guarantee

    @Test func editSucceedsWithoutLSP() async throws {
        let (dir, path) = tempFile(named: "a.txt")
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = EditFileTool(editQuality: nil)  // no LSP wired
        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("hello"),
            ]))
        #expect(!r.isError)
        #expect(r.content.contains("Edited") || r.content.contains("Create"))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "hello")
    }

    @Test func editSucceedsWhenNoServerConfiguredForLanguage() async throws {
        let (dir, path) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = LSPServerRegistry(persistence: InMemoryPersistenceStore())  // no configs at all
        let quality = EditQuality(registry: registry)
        let tool = EditFileTool(editQuality: quality)
        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("let x = 1"),
            ]))
        #expect(!r.isError)
        #expect(!r.content.contains("LSP diagnostics"))
    }

    @Test func editSucceedsWhenServerFailsToStart() async throws {
        let (dir, path) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [], fileGlobs: ["*.swift"], enabled: true)
        ])
        let registry = LSPServerRegistry(persistence: seeded(doc)) { _ in
            LSPClient(transport: FailingStartTransport())
        }
        let quality = EditQuality(registry: registry)
        let tool = EditFileTool(editQuality: quality)
        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("let x = 1"),
            ]))
        #expect(!r.isError)
        #expect(!r.content.contains("LSP diagnostics"))
    }

    @Test func editSucceedsWhenEveryLSPCallTimesOut() async throws {
        let (dir, path) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Answers `initialize` so the client connects, then goes silent for
        // everything else (didOpen has no response to wait on, but
        // `formatting` would hang forever without the client's own timeout).
        let silent = StubMCPTransport { message in
            guard let id = message["id"]?.stringValue,
                message["method"]?.stringValue == "initialize"
            else { return [] }
            return [
                .object([
                    "jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object(["capabilities": .object([:])]),
                ])
            ]
        }
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [], fileGlobs: ["*.swift"], enabled: true)
        ])
        let registry = LSPServerRegistry(persistence: seeded(doc)) { _ in
            LSPClient(transport: silent, requestTimeout: 0.05)
        }
        let quality = EditQuality(registry: registry, diagnosticsPollTimeout: 0.05)
        let tool = EditFileTool(editQuality: quality)
        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("let x = 1"),
            ]))
        #expect(!r.isError)
        #expect(!r.content.contains("LSP diagnostics"))
    }

    // MARK: - Advisory content when LSP IS available

    @Test func diagnosticsAreAttachedWhenServerPublishesThem() async throws {
        let (dir, path) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stub = StubMCPTransport { message in
            guard let id = message["id"]?.stringValue else {
                // didOpen notification triggers the server "pushing" diagnostics.
                if message["method"]?.stringValue == "textDocument/didOpen" {
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "method": .string("textDocument/publishDiagnostics"),
                            "params": .object([
                                "uri": .string("file://\(path)"),
                                "diagnostics": .array([
                                    .object([
                                        "range": .object([
                                            "start": .object(["line": .number(0), "character": .number(4)])
                                        ]),
                                        "severity": .number(1), "message": .string("expected ';'"),
                                    ])
                                ]),
                            ]),
                        ])
                    ]
                }
                return []
            }
            switch message["method"]?.stringValue {
            case "initialize":
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object(["capabilities": .object([:])]),
                    ])
                ]
            case "textDocument/formatting":
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id), "result": .null])]
            default:
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id), "result": .null])]
            }
        }
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [], fileGlobs: ["*.swift"], enabled: true)
        ])
        let registry = LSPServerRegistry(persistence: seeded(doc)) { _ in LSPClient(transport: stub) }
        let quality = EditQuality(registry: registry)
        let tool = EditFileTool(editQuality: quality)

        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("let x = 1"),
            ]))
        #expect(!r.isError)
        #expect(r.content.contains("LSP diagnostics"))
        #expect(r.content.contains("expected ';'"))
    }

    @Test func formattingEditsAreAppliedAndWrittenBack() async throws {
        let (dir, path) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stub = StubMCPTransport { message in
            guard let id = message["id"]?.stringValue else { return [] }
            switch message["method"]?.stringValue {
            case "initialize":
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object(["capabilities": .object([:])]),
                    ])
                ]
            case "textDocument/formatting":
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .array([
                            .object([
                                "range": .object([
                                    "start": .object(["line": .number(0), "character": .number(0)]),
                                    "end": .object(["line": .number(0), "character": .number(7)]),
                                ]),
                                "newText": .string("let x = 1"),
                            ])
                        ]),
                    ])
                ]
            default:
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id), "result": .null])]
            }
        }
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [], fileGlobs: ["*.swift"], enabled: true)
        ])
        let registry = LSPServerRegistry(persistence: seeded(doc)) { _ in LSPClient(transport: stub) }
        let quality = EditQuality(registry: registry, diagnosticsPollTimeout: 0.05)
        let tool = EditFileTool(editQuality: quality)

        let r = try await tool.execute(
            .object([
                "path": .string(path), "old_string": .string(""), "new_string": .string("let x=1"),
            ]))
        #expect(!r.isError)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "let x = 1")
    }
}

/// Transport whose `start()` always throws — deterministic handshake failure,
/// mirroring `LSPServerRegistryTests.FailingStartTransport` (private there).
private actor FailingStartTransport: MCPTransport {
    func start() async throws { throw MCPError.transport("boom") }
    func send(_ message: JSONValue) async throws {}
    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}
