import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// The migration's relocation table and the app's read paths must name the SAME
/// directories. A disagreement never fails, throws, or logs — the vault simply
/// comes up without the user's agents, provider connections or chat history,
/// which from their side is indistinguishable from data loss.
///
/// So these tests do not compare path strings. They write each document through
/// a store rooted at the LEGACY location, migrate, and then read it back through
/// a store rooted exactly the way `bootstrapCoreStores` / `bootstrapModelRouting`
/// / `bootstrapAgentSessionAndRuns` root theirs. If the two tables ever drift,
/// the load returns nil here.
@Suite("Vault layout agreement")
struct VaultLayoutAgreementTests {
    private let fm = FileManager.default

    private func legacyDocuments() throws -> (container: URL, documents: URL) {
        let container = fm.temporaryDirectory
            .appendingPathComponent("layout-\(UUID().uuidString)", isDirectory: true)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        return (container, documents)
    }

    /// Mirrors `AppEnvironment.bootstrapCoreStores`: the assistant's documents are
    /// rooted at `Sage/`, everything else at `Config/`, and chat history at
    /// `Sage/sessions/`.
    private func readPaths(_ home: Home) -> (
        config: PersistenceStore,
        assistant: PersistenceStore,
        sessions: PersistenceStore
    ) {
        (
            FileDocumentStore(rootURL: home.shared(.config)),
            FileDocumentStore(rootURL: home.shared(.agents)),
            FileDocumentStore(rootURL: home.shared(.sessions))
        )
    }

    @Test func migratedAssistantDocumentsAreFoundWhereTheAppReadsThem() throws {
        let (container, documents) = try legacyDocuments()
        defer { try? fm.removeItem(at: container) }
        let t = TestHome.make("layout1")
        defer { t.cleanup() }

        // Author the legacy tree through the same store type the pre-Home app
        // used, so the on-disk envelopes are exactly what a real user would have.
        let legacyStore = FileDocumentStore(rootURL: documents)
        let agentID = UUID()
        legacyStore.save(AgentsDocument(custom: [], activeID: agentID))
        legacyStore.save(ConnectionsDocument(connections: []))
        let sessionID = UUID()
        legacyStore.save(
            SageSessionsDocument(
                sessions: [
                    SavedSession(
                        id: sessionID, title: "Old chat",
                        createdAt: .init(timeIntervalSince1970: 1),
                        updatedAt: .init(timeIntervalSince1970: 2))
                ],
                activeID: sessionID))
        legacyStore.save(GlobalSettings())

        _ = try VaultMigration.migrate(fromContainer: container, into: t.home)

        let paths = readPaths(t.home)
        #expect(
            paths.assistant.load(AgentsDocument.self)?.activeID == agentID,
            "agents.json must be readable from Sage/")
        #expect(
            paths.assistant.load(ConnectionsDocument.self) != nil,
            "connections.json must be readable from Sage/")
        #expect(
            paths.sessions.load(SageSessionsDocument.self)?.sessions.first?.title == "Old chat",
            "chat history must be readable from Sage/sessions/")
        #expect(
            paths.config.load(GlobalSettings.self) != nil,
            "everything else stays in Config/")
    }

    /// The other direction: the assistant documents must NOT still be sitting in
    /// `Config/`, and the config store must not be able to see them — otherwise a
    /// half-applied change would pass the test above while leaving duplicates.
    @Test func assistantDocumentsDoNotLandInConfig() throws {
        let (container, documents) = try legacyDocuments()
        defer { try? fm.removeItem(at: container) }
        let t = TestHome.make("layout2")
        defer { t.cleanup() }

        let legacyStore = FileDocumentStore(rootURL: documents)
        legacyStore.save(AgentsDocument())
        legacyStore.save(ConnectionsDocument(connections: []))
        legacyStore.save(SageSessionsDocument())
        legacyStore.save(GlobalSettings())

        _ = try VaultMigration.migrate(fromContainer: container, into: t.home)

        let config = t.home.shared(.config)
        for name in ["agents.json", "connections.json", "assistant-sessions.json"] {
            #expect(
                !fm.fileExists(atPath: config.appendingPathComponent(name).path),
                "\(name) belongs under Sage/, not Config/")
        }
        #expect(fm.fileExists(atPath: config.appendingPathComponent("global-settings.json").path))
        let assistant = t.home.shared(.agents)
        #expect(fm.fileExists(atPath: assistant.appendingPathComponent("agents.json").path))
        #expect(fm.fileExists(atPath: assistant.appendingPathComponent("connections.json").path))
        #expect(
            fm.fileExists(
                atPath: t.home.shared(.sessions)
                    .appendingPathComponent("assistant-sessions.json").path))
    }

    /// Every top-level legacy JSON document must land in exactly one destination —
    /// the named rows and the catch-all row must partition, not overlap.
    @Test func everyLegacyJSONDocumentLandsInExactlyOnePlace() throws {
        let (container, documents) = try legacyDocuments()
        defer { try? fm.removeItem(at: container) }
        let t = TestHome.make("layout3")
        defer { t.cleanup() }

        let names = [
            "agents.json", "connections.json", "assistant-sessions.json",
            "global-settings.json", "app-appearance.json",
        ]
        for name in names {
            try #"{"payload":{}}"#.write(
                to: documents.appendingPathComponent(name),
                atomically: true, encoding: .utf8)
        }

        let report = try VaultMigration.migrate(fromContainer: container, into: t.home)

        #expect(
            report.copied.sorted() == names.sorted(),
            "each document copied exactly once: \(report.copied)")
        #expect(report.skipped.isEmpty)

        // And each is present at exactly one of the three roots.
        let roots = [t.home.shared(.config), t.home.shared(.agents), t.home.shared(.sessions)]
        for name in names {
            let hits = roots.filter { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }
            #expect(hits.count == 1, "\(name) landed in \(hits.count) roots")
        }
    }

    /// The relocation table's named sets are what keep the two halves in step, so
    /// they are asserted directly as well — a rename of a `documentID` that is not
    /// mirrored here would otherwise strand that document in `Config/`.
    @Test func theRelocatedDocumentNamesMatchTheDocumentIDs() {
        #expect(
            VaultMigration.assistantJSONNames == [
                "\(AgentsDocument.documentID).json",
                "\(ConnectionsDocument.documentID).json",
            ])
        #expect(
            VaultMigration.sessionJSONNames == [
                "\(SageSessionsDocument.documentID).json"
            ])
    }
}
