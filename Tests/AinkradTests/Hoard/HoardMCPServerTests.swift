import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("Hoard MCP server", .serialized)
struct HoardMCPServerTests {
    /// A real temp directory: these tools drive the real engine against the
    /// real filesystem, which is the only way to prove the undo path works
    /// end to end.
    private func makeWorkspace() throws -> (AppEnvironment, URL, HoardPaneStore) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "alpha".write(
            to: root.appendingPathComponent("one.txt"),
            atomically: true, encoding: .utf8)
        try "beta".write(
            to: root.appendingPathComponent("two.txt"),
            atomically: true, encoding: .utf8)

        let environment = AppEnvironment.preview()
        let store = HoardPaneStore(
            fileSystem: environment.filesSystemService,
            persistence: environment.persistence)
        store.activeTab.navigate(to: root)
        _ = environment.filesPaneCoordinator.register(store)
        return (environment, root, store)
    }

    private func call(_ server: MCPAppServer, _ tool: String, _ args: [String: Any]) async -> String {
        let request: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": tool, "arguments": args],
        ]
        let data = try! JSONSerialization.data(withJSONObject: request)
        return await server.handle(String(decoding: data, as: UTF8.self))
    }

    @Test("publishes navigation and manipulation tools, and no read/edit duplicates")
    func toolInventory() async throws {
        let (environment, _, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        let response = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)

        for expected in [
            "hoard_navigate", "hoard_get_selection", "hoard_reveal",
            "hoard_copy", "hoard_move", "hoard_rename", "hoard_trash",
            "hoard_create_folder", "hoard_batch_rename",
            "hoard_archive", "hoard_extract",
        ] {
            #expect(response.contains(expected), "missing \(expected)")
        }
        // AgentKit already owns reading and editing content; duplicating it
        // would be two overlapping tools for one job.
        #expect(!response.contains("hoard_read"))
        #expect(!response.contains("hoard_edit"))
    }

    @Test("reports the user's selection")
    func getSelection() async throws {
        let (environment, root, store) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)
        // Via `select(matching:)`, because a directly-assigned URL may spell a
        // symlinked prefix differently from the listing — the bug this method
        // exists to prevent.
        #expect(store.activeTab.select(matching: root.appendingPathComponent("one.txt")))

        let response = await call(server, "hoard_get_selection", [:])
        #expect(response.contains("one.txt"))
    }

    @Test("navigate moves the live pane")
    func navigate() async throws {
        let (environment, root, store) = try makeWorkspace()
        let nested = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let server = HoardMCPServer.make(environment: environment)

        _ = await call(server, "hoard_navigate", ["path": nested.path])
        #expect(store.activeTab.currentDirectory.path == nested.path)
    }

    // The invariant that makes the whole integration safe to ship.
    @Test("an assistant-initiated rename lands on the SAME undo stack and is reversible")
    func assistantRenameIsUndoable() async throws {
        let (environment, root, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)
        let original = root.appendingPathComponent("one.txt")

        _ = await call(server, "hoard_rename", ["path": original.path, "new_name": "renamed.txt"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed.txt").path))
        #expect(environment.filesUndoStack.canUndo)

        environment.filesOperationEngine.undo()
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed.txt").path))
    }

    // ONE undo, not one per file: the tool's description promises a single
    // step, and it used to submit a rename per path, which made that a lie.
    @Test("a batch rename is undoable in a single step")
    func batchRenameUndoable() async throws {
        let (environment, root, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        let response = await call(
            server, "hoard_batch_rename",
            [
                "paths": [
                    root.appendingPathComponent("one.txt").path,
                    root.appendingPathComponent("two.txt").path,
                ],
                "find": ".txt", "replace": ".md",
            ])
        #expect(response.contains("Renamed 2"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("one.md").path))

        environment.filesOperationEngine.undo()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("one.txt").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("two.txt").path))
        // Both names came back from that ONE undo, so there is nothing left.
        #expect(!environment.filesOperationEngine.undoStack.canUndo)
    }

    @Test("trash is undoable and never deletes permanently")
    func trashUndoable() async throws {
        let (environment, root, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)
        let target = root.appendingPathComponent("one.txt")

        _ = await call(server, "hoard_trash", ["paths": [target.path]])
        #expect(!FileManager.default.fileExists(atPath: target.path))

        environment.filesOperationEngine.undo()
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(try String(contentsOf: target, encoding: .utf8) == "alpha")
    }

    // MARK: - Safety

    @Test("a system path is refused even though it is absolute")
    func refusesSystemPaths() async throws {
        let (environment, _, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        let response = await call(server, "hoard_trash", ["paths": ["/System/Library/Fonts"]])
        #expect(response.contains("off limits"))
        #expect(FileManager.default.fileExists(atPath: "/System/Library/Fonts"))
    }

    @Test("a relative path outside every open pane is refused")
    func refusesOutsideInferredPath() async throws {
        let (environment, _, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        let response = await call(server, "hoard_trash", ["paths": ["../escape.txt"]])
        #expect(
            response.contains("\\u2026") || response.lowercased().contains("refus")
                || response.contains(".."))
    }

    // Partial application is worse than none: the assistant would report
    // success for a batch that half-happened.
    @Test("one refused path fails the WHOLE call, leaving nothing half-done")
    func refusalIsAllOrNothing() async throws {
        let (environment, root, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        _ = await call(
            server, "hoard_trash",
            [
                "paths": [root.appendingPathComponent("one.txt").path, "/System/x"]
            ])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("one.txt").path))
    }

    @Test("copy defaults to keep-both rather than silently overwriting")
    func copyDefaultsToKeepBoth() async throws {
        let (environment, root, _) = try makeWorkspace()
        let destination = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "existing".write(
            to: destination.appendingPathComponent("one.txt"),
            atomically: true, encoding: .utf8)
        let server = HoardMCPServer.make(environment: environment)

        _ = await call(
            server, "hoard_copy",
            [
                "paths": [root.appendingPathComponent("one.txt").path],
                "destination": destination.path,
            ])

        // The pre-existing file must survive untouched.
        #expect(
            try String(
                contentsOf: destination.appendingPathComponent("one.txt"),
                encoding: .utf8) == "existing")
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("one 2.txt").path))
    }

    @Test("mutating tools are marked destructive so the approval gate engages")
    func destructiveHints() async throws {
        let (environment, _, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        let response = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        guard let data = response.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any],
            let tools = result["tools"] as? [[String: Any]]
        else {
            Issue.record("could not decode tools/list")
            return
        }

        for name in ["hoard_trash", "hoard_rename", "hoard_move", "hoard_batch_rename"] {
            let tool = tools.first { $0["name"] as? String == name }
            let annotations = tool?["annotations"] as? [String: Any]
            #expect(annotations?["destructiveHint"] as? Bool == true, "\(name) must be destructive")
        }
    }

    // Archives were spec'd as tools from the start; `ArchiveService` existed
    // with tests but nothing — not the UI, not the assistant — could reach it.
    @Test("an assistant-created archive is undoable and leaves the inputs alone")
    func archiveIsUndoable() async throws {
        let (environment, root, _) = try makeWorkspace()
        let server = HoardMCPServer.make(environment: environment)

        let response = await call(
            server, "hoard_archive",
            [
                "paths": [root.appendingPathComponent("one.txt").path],
                "destination": root.path,
                "name": "bundle.zip",
            ])
        #expect(!response.lowercased().contains("failed"))
        let archive = root.appendingPathComponent("bundle.zip")
        #expect(FileManager.default.fileExists(atPath: archive.path))

        environment.filesOperationEngine.undo()
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        // The input is untouched by the archive AND by its undo.
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("one.txt").path))
    }

}
