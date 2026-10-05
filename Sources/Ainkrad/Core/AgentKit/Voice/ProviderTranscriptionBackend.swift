import Foundation

/// OpenAI-compatible Whisper STT over the Slice-5 connection/provider layer.
/// Uploads audio → explicit opt-in is enforced upstream (the selector); this
/// type just performs the request against a chosen connection.
struct ProviderTranscriptionBackend: TranscriptionService {
    let http: DataHTTPClient
    let connections: ConnectionStore
    let connectionID: UUID
    let model: String

    private struct Response: Decodable { let text: String }

    private static let contentTypes: [String: String] = [
        "m4a": "audio/m4a", "mp3": "audio/mpeg", "mpga": "audio/mpeg", "mpeg": "audio/mpeg",
        "wav": "audio/wav", "aiff": "audio/aiff", "aif": "audio/aiff", "caf": "audio/x-caf",
        "flac": "audio/flac", "mp4": "audio/mp4", "webm": "audio/webm", "ogg": "audio/ogg",
    ]

    @MainActor
    func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
        guard let connection = connections.connections.first(where: { $0.id == connectionID }) else {
            throw TranscriptionError.noConnection
        }
        let apiKey = connections.token(for: connection) ?? ""
        let base = connection.baseURL.hasSuffix("/") ? String(connection.baseURL.dropLast()) : connection.baseURL
        guard let url = URL(string: base + "/audio/transcriptions") else {
            throw TranscriptionError.provider("Invalid base URL")
        }

        var fields = ["model": model]
        if let localeIdentifier { fields["language"] = String(localeIdentifier.prefix(2)) }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let boundary = "ainkrad-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = MultipartForm.build(
            boundary: boundary, fields: fields,
            file: (
                name: "file", filename: fileName, data: audio,
                contentType: Self.contentTypes[ext] ?? "application/octet-stream"
            ))

        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw TranscriptionError.provider("HTTP \(response.statusCode)")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TranscriptionError.provider("Malformed transcription response")
        }
        return TranscriptionResult(text: decoded.text)
    }
}
