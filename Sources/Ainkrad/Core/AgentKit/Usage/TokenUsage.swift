import Foundation

/// Per-turn token counts accumulated from provider `.usage` events. `input`/`output`
/// are billed tokens; `cacheRead`/`cacheWrite` are prompt-cache tokens some providers
/// bill at a different rate (see `ModelPriceTable`, Task 7).
struct TokenUsage: Codable, Equatable, Sendable {
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int

    init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    static let zero = TokenUsage()

    static func + (l: TokenUsage, r: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: l.input + r.input, output: l.output + r.output,
            cacheRead: l.cacheRead + r.cacheRead, cacheWrite: l.cacheWrite + r.cacheWrite)
    }
}
