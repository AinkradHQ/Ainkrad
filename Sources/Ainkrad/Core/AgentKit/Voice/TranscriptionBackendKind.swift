import Foundation

/// Which speech-to-text backend transcribes captured/dropped audio.
enum TranscriptionBackendKind: String, Codable, Sendable, CaseIterable {
    case onDevice  // Apple Speech — private, offline, no key. Default.
    case provider  // Whisper/OpenAI-compatible over a configured connection. Opt-in.
}
