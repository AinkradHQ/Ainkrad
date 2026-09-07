import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Renders assistant transcript text as markdown blocks. Prose/heading/list
/// items resolve inline markdown via `AttributedString`; fenced code reuses
/// the kit's `AinkradCodeBlock` (mono chamfer surface + copy button). Block
/// parsing is incremental (see `MarkdownStreamParser`) and inline markdown
/// resolution is memoised via `InlineMarkdownCache`, so re-evaluating this
/// view on every streaming update stays cheap.
struct SageMarkdownText: View {
    let text: String
    let tokens: DesignTokens
    var typography: SageTypography = .init()

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let src):
            inline(src).font(typography.display(13)).foregroundStyle(tokens.foreground.opacity(0.9))
        case .heading(let level, let src):
            inline(src)
                .font(typography.display(headingSize(level), weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.95))
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(tokens.accentSecondary)
                        inline(item).foregroundStyle(tokens.foreground.opacity(0.9))
                    }
                    .font(typography.display(13))
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).").foregroundStyle(tokens.accentSecondary)
                        inline(item).foregroundStyle(tokens.foreground.opacity(0.9))
                    }
                    .font(typography.display(13))
                }
            }
        case .codeBlock(let language, let code):
            AinkradCodeBlock(code, language: language)
        case .thematicBreak:
            Rectangle()
                .fill(tokens.foreground.opacity(0.12))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }

    /// Resolves inline markdown (bold/italic/`code`/links) through a shared
    /// bounded cache — see `InlineMarkdownCache` for why. Never throws into
    /// the view; unparseable source renders as itself.
    private func inline(_ src: String) -> Text {
        Text(InlineMarkdownCache.attributed(src))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 18; case 2: return 16; default: return 14 }
    }
}
