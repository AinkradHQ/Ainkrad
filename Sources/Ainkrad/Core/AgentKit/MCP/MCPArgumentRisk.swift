import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/MCPArgumentRisk.swift
import Foundation

/// Generalizes the host's old git-only `optionLookingValue` check off git, so
/// the same argument-injection defense applies to every MCP tool, including
/// third-party servers. MCP's `destructiveHint` is a static per-tool boolean and cannot
/// express per-call irreversibility, so this rule walks the actual call
/// arguments: an option-looking value anywhere in the payload is dangerous
/// for any tool that reaches a CLI (`--upload-pack=<cmd>`, `--exec=<cmd>`,
/// `-c core.pager=<cmd>`, the `ext::` transport helper, …), regardless of
/// what the server claims about itself.
enum MCPArgumentRisk {
    /// True when any value reachable from `input` looks like a command-line
    /// option rather than plain data. Unlike the old git-only check, there is no
    /// `repoPath`/`args` shape to special-case here — a generic MCP payload
    /// is walked in full, top level included.
    static func hasOptionLookingValue(_ input: JSONValue) -> Bool {
        firstOptionLooking(input) != nil
    }

    /// One or two leading dashes IMMEDIATELY followed by an alphanumeric.
    ///
    /// DO NOT "simplify" this back to `hasPrefix("-")`. That was right when the
    /// only caller was Git Mage, whose every argument is a ref, a path or a
    /// flag. It is wrong for content-bearing tools: Lore's `create_note` and
    /// `save_note` carry markdown BODIES, so an ordinary bullet list (`- item`),
    /// a `---` rule, or a query starting with a dash tripped it — an approval
    /// prompt on the majority of benign writes, which is approval fatigue, which
    /// erodes the gate the whole split-tool design rests on.
    ///
    /// The discriminator: a CLI option's dash is followed by an alphanumeric
    /// (`-c`, `--exec=…`, `--upload-pack=…`, `--receive-pack=…`,
    /// `-o ProxyCommand=…`), whereas markdown's is followed by a SPACE
    /// (`- item`, `-- `) or by more dashes (`---`). Every attack form on the
    /// list this rule inherited from the old git-only check keeps flagging;
    /// prose stops. Three-plus dashes are markdown, never an option — no CLI
    /// parses `---x`.
    ///
    /// Prefix-only, exactly as before: this widens nothing, it only narrows.
    private static func looksLikeCLIOption(_ s: String) -> Bool {
        var rest = Substring(s)
        var dashes = 0
        while rest.first == "-" {
            dashes += 1
            rest = rest.dropFirst()
        }
        guard dashes == 1 || dashes == 2 else { return false }
        // `isLetter || isNumber` rather than ASCII-only: a non-ASCII option name
        // is unusual but not impossible, and this rule errs toward flagging.
        guard let next = rest.first else { return false }
        return next.isLetter || next.isNumber
    }

    /// Recurses into arrays and objects — an injected option nested one
    /// level down (`{"paths": ["--exec=…"]}`) is exactly as dangerous as a
    /// top-level one. Object walks are sorted-key so the result is
    /// deterministic across runs rather than flapping with dictionary order.
    private static func firstOptionLooking(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s):
            if looksLikeCLIOption(s) { return s }
            // `ext::sh -c …` is git's own transport-helper escape hatch: it
            // runs an arbitrary command, and it needs no leading dash to do
            // it. Kept here even off-git, since a generic CLI-backed MCP
            // server can shell out to git (or something like it) too.
            if s.lowercased().hasPrefix("ext::") { return s }
            return nil
        case .array(let items):
            for item in items { if let found = firstOptionLooking(item) { return found } }
            return nil
        case .object(let dict):
            for key in dict.keys.sorted() {
                if let v = dict[key], let found = firstOptionLooking(v) { return found }
            }
            return nil
        default:
            return nil
        }
    }
}
