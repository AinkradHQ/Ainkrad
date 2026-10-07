import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillInstaller")
@MainActor
struct SkillInstallerTests {
    private struct StubHTTP: HTTPClient {
        let payload: [URL: Data]
        func get(_ url: URL) async throws -> Data {
            guard let d = payload[url] else { throw HTTPError.status(404) }
            return d
        }
    }

    private func entry(_ contentURL: String, appID: String = "pdf-processing", version: String = "1.0") -> CatalogEntry
    {
        CatalogEntry(
            appID: appID, displayName: "PDF Processing", icon: "doc",
            description: "work with PDFs", version: version, apiVersion: 0,
            downloadURL: URL(string: "https://e/none")!, sha256: "", sourceRepo: "o/r",
            kind: .skill, skill: SkillCatalogDescriptor(contentURL: URL(string: contentURL)!))
    }

    @Test func installFetchesValidatesWritesAndRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("si-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://e/pdf/SKILL.md")!
        let md = "---\nname: pdf-processing\ndescription: work with PDFs\n---\nStep 1"
        let persistence = InMemoryPersistenceStore()
        let installer = SkillInstaller(
            http: StubHTTP(payload: [url: Data(md.utf8)]),
            paths: SkillPaths(root: root), persistence: persistence)
        try await installer.install(entry(url.absoluteString))
        let file = SkillPaths(root: root).skillFile("pdf-processing")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["pdf-processing"]?.version == "1.0")
    }

    @Test func installIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("si-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://e/pdf/SKILL.md")!
        let md = "---\nname: pdf-processing\ndescription: work with PDFs\n---\nStep 1"
        let persistence = InMemoryPersistenceStore()
        let installer = SkillInstaller(
            http: StubHTTP(payload: [url: Data(md.utf8)]),
            paths: SkillPaths(root: root), persistence: persistence)
        try await installer.install(entry(url.absoluteString))
        try await installer.install(entry(url.absoluteString))
        let dir = SkillPaths(root: root).skillDir("pdf-processing")
        let children = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(children == ["SKILL.md"])
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed.count == 1)
    }

    @Test func rejectsMalformedContent() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("si-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://e/bad/SKILL.md")!
        let installer = SkillInstaller(
            http: StubHTTP(payload: [url: Data("not a skill".utf8)]),
            paths: SkillPaths(root: root), persistence: InMemoryPersistenceStore())
        await #expect(throws: AppStoreError.self) {
            try await installer.install(entry(url.absoluteString))
        }
        #expect(!FileManager.default.fileExists(atPath: SkillPaths(root: root).skillFile("pdf-processing").path))
    }

    @Test func fetchFailureFailsGracefully() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("si-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://e/missing/SKILL.md")!
        let installer = SkillInstaller(
            http: StubHTTP(payload: [:]),
            paths: SkillPaths(root: root), persistence: InMemoryPersistenceStore())
        await #expect(throws: (any Error).self) {
            try await installer.install(entry(url.absoluteString))
        }
        #expect(!FileManager.default.fileExists(atPath: SkillPaths(root: root).skillFile("pdf-processing").path))
    }

    @Test func rejectsTraversalName() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("si-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://e/evil/SKILL.md")!
        let md = "---\nname: pdf-processing\ndescription: d\n---\nsteps"
        let installer = SkillInstaller(
            http: StubHTTP(payload: [url: Data(md.utf8)]),
            paths: SkillPaths(root: root), persistence: InMemoryPersistenceStore())
        let maliciousEntry = entry(url.absoluteString, appID: "../../evil")
        await #expect(throws: AppStoreError.self) {
            try await installer.install(maliciousEntry)
        }
        // Nothing should exist outside root, and root itself should not have escaped content.
        let escaped = root.deletingLastPathComponent().appendingPathComponent("evil")
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
    }

    @Test func uninstallRemovesFilesAndState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("si-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(string: "https://e/pdf/SKILL.md")!
        let md = "---\nname: pdf-processing\ndescription: d\n---\nsteps"
        let persistence = InMemoryPersistenceStore()
        let installer = SkillInstaller(
            http: StubHTTP(payload: [url: Data(md.utf8)]),
            paths: SkillPaths(root: root), persistence: persistence)
        try await installer.install(entry(url.absoluteString))
        try installer.uninstall(appID: "pdf-processing")
        #expect(!FileManager.default.fileExists(atPath: SkillPaths(root: root).skillDir("pdf-processing").path))
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["pdf-processing"] == nil)
    }
}
