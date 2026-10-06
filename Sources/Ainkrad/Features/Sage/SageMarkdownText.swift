import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Renders assistant transcript text as markdown blocks. Prose/heading/list
/// items resolve inline markdown via `AttributedString`; fenced code reuses
/// the kit's `AinkradCodeBlock` (mono chamfer surface + copy button). Block
/// parsing is incremental (see `MarkdownStreamParser`) and inline markdown
/// resolution is memoised via `InlineMarkdownCache`, so re-evaluating this
/// view on every streaming update stays cheap.
struct SageMarkdownText: View {
    @Environment(\.ainkradSkin) private var skin
    private let blocks: [MarkdownBlock]
    @Environment(\.ainkradTheme) private var theme
    var typography: AinkradTypography

    /// Primary path for streaming: blocks are already parsed incrementally by
    /// `MarkdownStreamParser`, so this does no parsing at all.
    init(blocks: [MarkdownBlock], typography: AinkradTypography = .default) {
        self.blocks = blocks
        self.typography = typography
    }

    /// Committed transcript messages, which are parsed once and never change.
    init(text: String, typography: AinkradTypography = .default) {
        self.init(blocks: MarkdownBlocks.parse(text), typography: typography)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let src):
            inline(src).font(AinkradFontResolver.font(size: 13, typography: typography)).foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
        case .heading(let level, let src):
            inline(src)
                .font(AinkradFontResolver.font(size: headingSize(level), weight: .semibold, typography: typography))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o95))
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: skin.size.s3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: skin.size.s6) {
                        Text("•").foregroundStyle(theme.accentSecondary)
                        inline(item).foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
                    }
                    .font(AinkradFontResolver.font(size: 13, typography: typography))
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: skin.size.s3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: skin.size.s6) {
                        Text("\(idx + 1).").foregroundStyle(theme.accentSecondary)
                        inline(item).foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
                    }
                    .font(AinkradFontResolver.font(size: 13, typography: typography))
                }
            }
        case .codeBlock(let language, let code):
            AinkradCodeBlock(code, language: language)
        case .thematicBreak:
            Rectangle()
                .fill(theme.foreground.opacity(skin.opacity.o12))
                .frame(height: skin.size.s1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, skin.spacing.xs)
        }
    }

    /// Resolves inline markdown (bold/italic/`code`/links) through a shared
    /// bounded cache — see `InlineMarkdownCache` for why. Never throws into
    /// the view; unparseable source renders as itself.
    private func inline(_ src: String) -> Text {
        Text(InlineMarkdownCache.attributed(src))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 18
        case 2: return 16
        default: return 14
        }
    }
}
