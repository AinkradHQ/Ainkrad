import Foundation

/// One diagnostic record. Pure value type with no I/O so the encoding is unit
/// tested independently of the file writer — the writer only appends bytes.
///
/// NDJSON (one JSON object per line) rather than a JSON array: the file is
/// append-only and may be truncated by a crash mid-write, and a partial NDJSON
/// file still parses line-by-line up to the damage. A partial array does not.
struct CrashReport: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case uncaughtException
        case hang
        case diskWriteException
        case cpuException
        case crashDiagnostic
    }

    let kind: Kind
    let timestamp: Date
    let appVersion: String
    let summary: String
    let detail: String
    let stack: [String]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // NOT .prettyPrinted — see the NDJSON note above.
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func ndjsonLine() throws -> Data {
        var data = try Self.encoder.encode(self)
        data.append(0x0A)  // "\n"
        return data
    }

    static func decode(ndjsonLine: Data) throws -> CrashReport {
        let trimmed = ndjsonLine.last == 0x0A ? ndjsonLine.dropLast() : ndjsonLine[...]
        return try decoder.decode(CrashReport.self, from: Data(trimmed))
    }
}
