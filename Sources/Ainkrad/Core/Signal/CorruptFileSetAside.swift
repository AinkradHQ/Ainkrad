import AinkradHostRuntime
import Foundation

/// S-ERR-6 for the file-backed signal stores. Stateless on purpose: `load()` and `save()` both
/// call it, so a store never needs a `canSave` flag and a caller that saves without loading first
/// is covered too.
///
/// Returns true when it is safe to write `url`: the file is missing, decodes as `T`, or its bytes
/// were renamed to `<name>.corrupt-<UTC stamp>`. Returns false when the bytes are undecodable and
/// could not be set aside - the caller must then leave the file alone.
func setAsideIfUndecodable<T: Decodable>(_ type: T.Type, at url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url) else { return true }
    let error: any Error
    do {
        _ = try JSONDecoder().decode(T.self, from: data)
        return true
    } catch let decodeError {
        error = decodeError
    }
    let stamp = Date().formatted(.iso8601.dateSeparator(.omitted).timeSeparator(.omitted))
    let backup = url.deletingLastPathComponent()
        .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
    do {
        try FileManager.default.moveItem(at: url, to: backup)
        Log.persistence.error(
            "\(url.lastPathComponent, privacy: .public) does not decode; moved to \(backup.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
        return true
    } catch {
        Log.persistence.error(
            "\(url.lastPathComponent, privacy: .public) does not decode and could not be set aside; saving is off: \(error.localizedDescription, privacy: .public)"
        )
        return false
    }
}
