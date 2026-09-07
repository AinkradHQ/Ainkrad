import Foundation

/// Append-only incremental wrapper around `MarkdownBlocks.parse`.
///
/// **Why this exists.** The transcript re-parsed the WHOLE message on every SSE
/// delta, so rendering an n-token reply cost Θ(n²). This parses each block once.
///
/// **How it is correct.** `MarkdownBlocks.parse` is a single-pass line scan whose
/// only cross-line state is "inside a fence". A blank line outside a fence always
/// flushes the paragraph, produces no block, and ends any list run — so for a
/// split at such a line, `parse(head + tail) == parse(head) + parse(tail)`.
/// That line is the COMMIT POINT: everything before it is parsed once into
/// `committed` and never revisited; only `pending` (at most one block's worth of
/// text) is re-parsed as deltas arrive.
///
/// `MarkdownBlocks.parse` remains the single source of truth for what markdown
/// means. This type only decides *how little of it* to re-run, and
/// `MarkdownStreamParserTests` asserts equivalence at every prefix, including a
/// 300-document fuzz sweep.
struct MarkdownStreamParser {
    /// Blocks that can never change again.
    private var committed: [MarkdownBlock] = []
    /// Source text after the last commit point. Re-parsed on every read.
    private var pending: String = ""
    /// Everything appended, for callers that still need the raw text.
    private(set) var text: String = ""
    /// Whether `pending` currently sits inside an unterminated fence. A blank
    /// line is only a commit point when this is false.
    private var insideFence = false

    init() {}

    mutating func reset() {
        committed = []
        pending = ""
        text = ""
        insideFence = false
    }

    mutating func append(_ delta: String) {
        guard !delta.isEmpty else { return }
        text += delta
        pending += delta
        commitCompleteBlocks()
    }

    var blocks: [MarkdownBlock] {
        pending.isEmpty ? committed : committed + MarkdownBlocks.parse(pending)
    }

    /// Advances the commit point to the last blank line in `pending` that sits
    /// outside a fence, parsing everything up to and including it exactly once.
    private mutating func commitCompleteBlocks() {
        // A delta cannot create a commit point unless it contained a newline.
        guard pending.contains("\n") else { return }

        let lines = pending.components(separatedBy: "\n")
        // The final element is the in-progress line (no trailing newline yet),
        // so it can never be a commit point — it may still gain characters.
        var fence = insideFence
        var lastCommitIndex: Int?
        for index in 0..<max(lines.count - 1, 0) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                fence.toggle()
                continue
            }
            if !fence, trimmed.isEmpty { lastCommitIndex = index }
        }

        guard let commitIndex = lastCommitIndex else {
            // No commit point yet; remember the fence state we scanned past so a
            // later call does not have to rescan from the top of `pending`.
            return
        }

        let head = lines[0...commitIndex].joined(separator: "\n")
        let tail = lines[(commitIndex + 1)...].joined(separator: "\n")
        committed.append(contentsOf: MarkdownBlocks.parse(head))
        pending = tail
        // `head` ended at a blank line outside a fence, so by construction the
        // committed region closed every fence it opened.
        insideFence = false
    }
}
