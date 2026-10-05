import Foundation
import SQLite3

struct MemorySearchHit: Equatable {
    let source: String
    let title: String
    let snippet: String
}

enum MemoryIndexError: Error {
    case open(String)
    case exec(String)
}

/// FTS5 full-text index over memory files + session summaries. Derived + rebuildable.
final class MemoryIndex {
    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = lastError
            if db != nil { sqlite3_close(db) }
            throw MemoryIndexError.open(message)
        }
        try exec(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts
            USING fts5(source UNINDEXED, title, body);
            """)
    }

    deinit { if db != nil { sqlite3_close(db) } }

    func upsert(source: String, title: String, body: String) {
        deleteRows(source: source)
        let sql = "INSERT INTO memory_fts(source, title, body) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, source)
        bind(stmt, 2, title)
        bind(stmt, 3, body)
        sqlite3_step(stmt)
    }

    func search(_ query: String, limit: Int = 20) -> [MemorySearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sql = """
            SELECT source, title, snippet(memory_fts, 2, '', '', '…', 12)
            FROM memory_fts WHERE memory_fts MATCH ? ORDER BY rank LIMIT ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, ftsQuery(trimmed))
        let clampedLimit = Int32(min(max(limit, 0), Int(Int32.max)))
        sqlite3_bind_int(stmt, 2, clampedLimit)
        var hits: [MemorySearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            hits.append(
                MemorySearchHit(
                    source: column(stmt, 0), title: column(stmt, 1), snippet: column(stmt, 2)))
        }
        return hits
    }

    func clear() { try? exec("DELETE FROM memory_fts;") }

    // MARK: - helpers
    private func deleteRows(source: String) {
        let sql = "DELETE FROM memory_fts WHERE source = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, source)
        sqlite3_step(stmt)
    }

    /// Wrap each token as a prefix query, quoting to neutralize FTS5 syntax.
    private func ftsQuery(_ raw: String) -> String {
        raw.split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
            .joined(separator: " ")
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw MemoryIndexError.exec(lastError)
        }
    }
    private func bind(_ stmt: OpaquePointer?, _ i: Int32, _ value: String) {
        sqlite3_bind_text(stmt, i, value, -1, Self.SQLITE_TRANSIENT)
    }
    private func column(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
    }
    private var lastError: String { String(cString: sqlite3_errmsg(db)) }
}
