import AinkradHostRuntime
// Tests/AinkradTests/LSPWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("LSP wiring")
@MainActor
struct LSPWiringTests {
    @Test func editToolAcceptsEditQuality() {
        let registry = LSPServerRegistry(persistence: InMemoryPersistenceStore())
        let tool = EditFileTool(editQuality: EditQuality(registry: registry))
        #expect(tool.name == "edit_file")  // constructs without error
    }

    @Test func seedIfEmptyPopulatesAnEmptyDocument() {
        let persistence = InMemoryPersistenceStore()
        let registry = LSPServerRegistry(persistence: persistence)
        let configs = [
            LSPServerConfig(
                id: "swift", command: "/usr/bin/sourcekit-lsp",
                fileGlobs: ["*.swift"], enabled: true)
        ]

        registry.seedIfEmpty(with: configs)

        #expect(registry.language(forFilePath: "/x/File.swift") == "swift")
        #expect(persistence.load(LSPServersDocument.self)?.servers == configs)
    }

    @Test func seedIfEmptyNeverClobbersExistingUserConfigs() {
        let persistence = InMemoryPersistenceStore()
        let existing = LSPServersDocument(servers: [
            LSPServerConfig(id: "python", command: "/custom/pyright", fileGlobs: ["*.py"], enabled: true)
        ])
        persistence.save(existing)
        let registry = LSPServerRegistry(persistence: persistence)

        let autodetected = [
            LSPServerConfig(
                id: "swift", command: "/usr/bin/sourcekit-lsp",
                fileGlobs: ["*.swift"], enabled: true)
        ]
        registry.seedIfEmpty(with: autodetected)

        #expect(registry.language(forFilePath: "/x/File.swift") == nil)
        #expect(persistence.load(LSPServersDocument.self)?.servers == existing.servers)
    }
}
