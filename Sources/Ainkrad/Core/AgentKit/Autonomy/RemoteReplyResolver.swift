import Foundation

/// Builds the JSON reply body for a `GET /result/<runID>` on the remote channel.
/// Terminal runs return their result text; in-flight runs return their status.
@MainActor
enum RemoteReplyResolver {
    static func body(forRunID id: String, in runs: RunManager) -> String {
        guard let run = runs.runs.first(where: { $0.id.uuidString == id }) else {
            return encode(["status": "unknown"])
        }
        return encode(["status": run.status.rawValue, "result": run.result ?? ""])
    }

    /// Serialize via `JSONSerialization` so a result containing backslashes,
    /// quotes, newlines, or other control characters — routine in terminal/agent
    /// output — is properly escaped into valid JSON (manual quote-replacement is
    /// not enough and yields a body most parsers reject).
    private static func encode(_ object: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"status\":\"unknown\"}"
        }
        return json
    }
}
