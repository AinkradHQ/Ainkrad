import AinkradHostRuntime
import Foundation

/// One structured block of a turn. Tool use requires structured content, so a
/// message is a sequence of these rather than a bare string. A `tool_result`
/// rides inside a *user* message on both Claude and OpenAI wire formats, so no
/// new role is needed.
enum AgentContentBlock: Equatable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    /// An attached image. `mediaType` is a sniffed MIME type (e.g. `image/png`);
    /// `base64` is the raw file bytes, base64-encoded (see `ImageAttachment`).
    case image(mediaType: String, base64: String)
    /// Model reasoning captured during a turn. DISPLAY-ONLY: persisted for the
    /// transcript timeline, never sent back to a provider (see `wireContent`).
    case thinking(String)
}

struct AgentMessage: Equatable, Sendable {
    enum Role: String, Sendable, Codable { case user, assistant }
    var role: Role
    var content: [AgentContentBlock]

    init(role: Role, content: [AgentContentBlock]) {
        self.role = role
        self.content = content
    }

    /// Convenience for the common text-only turn (keeps Slice-1 call sites working).
    init(role: Role, text: String) {
        self.role = role
        self.content = [.text(text)]
    }

    /// Concatenation of the text blocks — what the transcript renders.
    var text: String {
        content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
    }

    /// Content minus display-only `.thinking` blocks — what every provider sends
    /// on the wire. Thinking is reconstructed provider-side and must never be
    /// echoed back as message content.
    var wireContent: [AgentContentBlock] {
        content.filter { if case .thinking = $0 { return false } else { return true } }
    }

    /// Concatenation of the thinking blocks — mirrors `text`.
    var thinkingText: String {
        content.compactMap { if case .thinking(let t) = $0 { return t } else { return nil } }.joined()
    }
}
