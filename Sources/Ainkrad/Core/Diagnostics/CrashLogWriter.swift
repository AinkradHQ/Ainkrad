import Foundation

/// Append-only NDJSON diagnostics log with a hard size cap.
///
/// **Never throws and never traps.** This runs from an uncaught-exception
/// handler — a process that is already dying. Anything that could fail a second
/// time there turns a diagnosable crash into an undiagnosable one, so every
/// failure path here degrades to "write nothing" and logs to `os.Logger`.
///
/// Rotation keeps exactly one previous generation (`diagnostics.ndjson.1`).
/// Two files bounded at `maxBytes` each is the whole retention policy: enough
/// to survive a crash loop, small enough never to matter on disk.
final class CrashLogWriter: @unchecked Sendable {
    private let directory: URL
    private let maxBytes: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    let fileURL: URL

    // Internal seam for testing: allows injection of a custom append implementation
    internal let appendBytes: (Data, URL) throws -> Void

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ainkrad", isDirectory: true)
    }

    init(directory: URL, maxBytes: Int = 1_048_576, fileManager: FileManager = .default) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent("diagnostics.ndjson")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.appendBytes = Self.defaultAppendBytes
    }

    // Internal initializer for testing with a custom appendBytes implementation
    internal init(directory: URL, maxBytes: Int = 1_048_576, fileManager: FileManager = .default, appendBytes: @escaping (Data, URL) throws -> Void) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent("diagnostics.ndjson")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.appendBytes = appendBytes
    }

    private static func defaultAppendBytes(data: Data, to fileURL: URL) throws {
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    func append(_ report: CrashReport) {
        guard let line = try? report.ndjsonLine() else {
            Log.diagnostics.error("Failed to encode a crash report; dropping it")
            return
        }
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded(incoming: line.count)
        do {
            try appendBytes(line, fileURL)
        } catch {
            // Do NOT fall back to `line.write(to:options:.atomic)` here. Unlike the
            // case where `FileHandle(forWritingTo:)` fails (file does not exist yet) —
            // reaching this catch means the file EXISTS and holds earlier records.
            // An atomic write would replace all of them with this one line.
            // Losing the newest record is survivable; losing the crash trail is not.
            // A partially-written tail line is fine: `readAll` drops undecodable lines.
            Log.diagnostics.error("Failed to append to crash log; dropping this record: \(error)")
        }
    }

    func readAll() -> [CrashReport] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // `try?` per line, deliberately: a crash mid-write leaves a truncated
        // final line, and every good record before it must still be readable.
        return data.split(separator: 0x0A).compactMap {
            try? CrashReport.decode(ndjsonLine: Data($0))
        }
    }

    /// Rotates when the current file plus the incoming line would exceed the cap.
    /// Caller holds `lock`.
    private func rotateIfNeeded(incoming: Int) {
        let size = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size + incoming > maxBytes else { return }
        let rotated = fileURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: fileURL, to: rotated)
    }
}
