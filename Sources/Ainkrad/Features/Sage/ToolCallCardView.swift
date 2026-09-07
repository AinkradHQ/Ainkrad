import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// A tool call in the transcript timeline. Collapsed, it is a lightweight row —
/// icon + name only (no card chrome), with a chevron that reveals on hover.
/// Clicking the row expands the result as a code block. While running, the row
/// (icon / text / chevron) breathes. Errors tint the row red and auto-expand so
/// an error is never hidden behind a click. The pending-approval preview always
/// shows its body (summary + diff) with an accent frame.
struct ToolCallCardView: View {
    /// Raw registered tool name (e.g. "edit_file") — identity only, drives icon/tint.
    var toolName: String
    let title: String
    let summary: String
    let diff: String?
    let tokens: DesignTokens
    /// True for the inline card of a tool currently awaiting approval: forces the
    /// body open and draws an accent frame.
    var pendingApproval: Bool = false
    /// Present for committed transcript cards; nil for the approval card.
    var result: ToolResultSummary?
    /// Structured diff for rich hunk review; when present with `pendingApproval`,
    /// the card renders `DiffReviewView` instead of the raw diff text.
    var fileDiff: FileDiff? = nil
    var rejectedHunkIDs: Binding<Set<Int>>? = nil
    /// A `data:` image URL (e.g. from `image_generate`) rendered inline below the
    /// row, so a generated image appears in the transcript, not only on the canvas.
    var imageDataURL: String? = nil
    /// Presents the inline image full-screen (handled at the window root).
    var onOpenImage: ((NSImage) -> Void)? = nil
    /// A `file:`/`http:` video URL (e.g. from `video_generate`) rendered inline.
    var videoURL: String? = nil
    /// Presents the inline video full-screen (handled at the window root).
    var onOpenVideo: ((URL) -> Void)? = nil
    /// A `file:` audio URL (e.g. from `speak`) rendered inline with playback + download.
    var audioURL: String? = nil

    @State private var isExpanded = false
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var presentation: ToolPresentation { ToolPresentation.for(toolName: toolName) }
    private var tint: Color { presentation.tint == .primary ? tokens.accentPrimary : tokens.accentSecondary }
    private var isError: Bool { result?.isError == true }
    private var isPending: Bool { result?.isPending == true }

    /// A completed, non-approval call the user can toggle open.
    private var canExpand: Bool { result != nil && !pendingApproval && !isPending }
    /// Body (code block) shows when the user expanded it, it errored (never hide
    /// an error), or it's the pending-approval preview.
    private var showsBody: Bool { isExpanded || isError || pendingApproval }
    /// Chevron reveals on hover for an expandable call; also shown while running
    /// (part of the running motion) and whenever the body is open.
    private var showsChevron: Bool { (isHovering && canExpand) || isPending || isExpanded }

    private var iconColor: Color { isError ? tokens.danger : tint }
    private var textColor: Color { isError ? tokens.danger : tokens.foreground.opacity(0.85) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if pendingApproval, let fileDiff, let rejectedHunkIDs, !fileDiff.hunks.isEmpty {
                DiffReviewView(fileDiff: fileDiff, rejectedHunkIDs: rejectedHunkIDs, tokens: tokens)
            } else if showsBody {
                codeBlock
            }
            if let imageDataURL {
                GeneratedImageView(dataURL: imageDataURL, tokens: tokens, onOpen: onOpenImage)
            }
            if let videoURL {
                GeneratedVideoView(urlString: videoURL, tokens: tokens, onOpen: onOpenVideo)
            }
            if let audioURL {
                GeneratedAudioView(urlString: audioURL, title: "Speech", tokens: tokens)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header (the collapsed, clickable row)

    private var header: some View {
        let row = HStack(spacing: 6) {
            Image(systemName: presentation.icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
            Text(title)
                .font(AinkradFont.display(12, weight: .semibold))
                .foregroundStyle(textColor)
            if showsChevron {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(reduceMotion ? nil : AinkradMotion.present) { isExpanded.toggle() }
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: showsChevron)

        // Running: breathe the whole row (icon / text / chevron) together.
        return Group {
            if isPending && !reduceMotion {
                BudgetedTimelineView { date in
                    let wave = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate / AinkradMotion.durationBase)
                    row.opacity(0.5 + 0.5 * wave)
                }
            } else {
                row
            }
        }
    }

    // MARK: - Body (the expanded code block)

    private var codeBlock: some View {
        Group {
            if let diff, !diff.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(diffGutterAttributed(diff)).font(AinkradFont.mono(11)).textSelection(.enabled)
                }
            } else if !summary.isEmpty {
                Text(summary)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(isError ? 0.9 : 0.7))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 260)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.background.opacity(0.45)))
        .overlay {
            ChamferShape(cut: AinkradRadius.sm)
                .stroke((isError ? tokens.danger : (pendingApproval ? tokens.accentPrimary : tint)).opacity(pendingApproval ? 0.5 : 0.22),
                        lineWidth: 1)
        }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: -4)))
    }

    private func diffGutterAttributed(_ diff: String) -> AttributedString {
        var out = AttributedString()
        for (i, line) in diff.components(separatedBy: "\n").enumerated() {
            let sign = line.first
            let gutter = sign == "+" ? "+ " : (sign == "-" ? "- " : "  ")
            var seg = AttributedString((i == 0 ? "" : "\n") + gutter + line.dropFirst(sign == "+" || sign == "-" ? 1 : 0))
            if sign == "+" { seg.foregroundColor = tokens.success }
            else if sign == "-" { seg.foregroundColor = tokens.danger }
            else { seg.foregroundColor = tokens.foreground.opacity(0.6) }
            out += seg
        }
        return out
    }
}
