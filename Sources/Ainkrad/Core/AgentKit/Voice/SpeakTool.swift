import Foundation
import AVFoundation
import AinkradHostRuntime

/// Text-to-speech seam. `SystemSpeechSynthesizer` uses on-device AVFoundation
/// (no key, no network) — reusing the Voice subsystem rather than a provider.
protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String)
}

struct SystemSpeechSynthesizer: SpeechSynthesizing {
    // AVSpeechSynthesizer must outlive the call; hold one shared instance.
    // `AVSpeechSynthesizer` isn't Sendable, so the shared instance is pinned
    // to the main actor (matching `AgentTool`'s @MainActor isolation).
    @MainActor static let shared = AVSpeechSynthesizer()
    func speak(_ text: String) {
        MainActor.assumeIsolated {
            Self.shared.speak(AVSpeechUtterance(string: text))
        }
    }
}

struct SpeakTool: AgentTool {
    let synth: any SpeechSynthesizing
    /// When present (with `store`), speech is rendered to a file and shown as a
    /// downloadable audio card in the transcript, not just played. Defaulted so
    /// existing call sites/tests compile unchanged.
    var producer: (any SpeechAudioProducing)? = nil
    var store: ScryStore? = nil
    let mediaStore: GeneratedMediaStore
    var player: any AudioPlaying = SystemAudioPlayer()

    let name = "speak"
    let description = "Speak text aloud on the user's machine using text-to-speech."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object(["type": .string("string"),
                                 "description": .string("Text to speak aloud.")]),
            ]),
            "required": .array([.string("text")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let text = input["text"]?.stringValue, !text.isEmpty else {
            throw ToolError.message("speak requires non-empty \"text\".")
        }
        // Preferred path: render audio to a file → play it → show a downloadable
        // audio card. Falls back to fire-and-forget playback on any failure.
        if let producer, let store {
            do {
                let (data, ext) = try await producer.audio(for: text)
                let url = try mediaStore.write(data, fileExtension: ext)
                player.play(data)
                let element = ScryElement(
                    id: UUID().uuidString, kind: .audio,
                    title: "Speech", body: url.absoluteString,
                    sizeHint: .medium)
                let id = store.add(element)
                return ToolResult(content: "Spoke \(text.count) characters (audio element \(id)).", isError: false)
            } catch {
                synth.speak(text)
                return ToolResult(content: "Spoke \(text.count) characters.", isError: false)
            }
        }
        synth.speak(text)
        return ToolResult(content: "Spoke \(text.count) characters.", isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Speak", summary: input["text"]?.stringValue ?? "?", diff: nil)
    }
}
