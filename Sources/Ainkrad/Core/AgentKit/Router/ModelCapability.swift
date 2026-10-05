import Foundation

/// Model capability flags used by the Model Router to filter candidates that
/// can satisfy a request (e.g. vision input, tool use, adjustable reasoning effort).
struct ModelCapability: OptionSet, Codable, Sendable {
    let rawValue: Int

    static let vision = ModelCapability(rawValue: 1 << 0)
    static let toolUse = ModelCapability(rawValue: 1 << 1)
    static let reasoningEffort = ModelCapability(rawValue: 1 << 2)
}
