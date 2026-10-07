import AinkradHostRuntime
import Foundation

// Manual Codable for the block enum — associated values need an explicit
// discriminator. Mirrors the wire shape loosely but is an internal on-disk
// format (session history), not the provider wire format.
extension AgentContentBlock: Codable {
    private enum Kind: String, Codable { case text, thinking, toolUse, toolResult, image }
    private enum CodingKeys: String, CodingKey {
        case kind, text, id, name, input, toolUseID, content, isError, mediaType, base64
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode(Kind.text, forKey: .kind)
            try c.encode(t, forKey: .text)
        case .thinking(let t):
            try c.encode(Kind.thinking, forKey: .kind)
            try c.encode(t, forKey: .text)
        case .toolUse(let id, let name, let input):
            try c.encode(Kind.toolUse, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try c.encode(Kind.toolResult, forKey: .kind)
            try c.encode(toolUseID, forKey: .toolUseID)
            try c.encode(content, forKey: .content)
            try c.encode(isError, forKey: .isError)
        case .image(let mediaType, let base64):
            try c.encode(Kind.image, forKey: .kind)
            try c.encode(mediaType, forKey: .mediaType)
            try c.encode(base64, forKey: .base64)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))
        case .thinking:
            self = .thinking(try c.decode(String.self, forKey: .text))
        case .toolUse:
            self = .toolUse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                input: try c.decode(JSONValue.self, forKey: .input))
        case .toolResult:
            self = .toolResult(
                toolUseID: try c.decode(String.self, forKey: .toolUseID),
                content: try c.decode(String.self, forKey: .content),
                isError: try c.decode(Bool.self, forKey: .isError))
        case .image:
            self = .image(
                mediaType: try c.decode(String.self, forKey: .mediaType),
                base64: try c.decode(String.self, forKey: .base64))
        }
    }
}

extension AgentMessage: Codable {
    private enum CodingKeys: String, CodingKey { case role, content }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            role: try c.decode(Role.self, forKey: .role),
            content: try c.decode([AgentContentBlock].self, forKey: .content))
    }
}
