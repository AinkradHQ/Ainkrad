import AinkradAppKit
import AinkradAppKitUI
import QuickLookUI
import SwiftUI

/// The collapsible right-hand preview strip. ⌘Y toggles it, matching Quick
/// Look's muscle memory.
///
/// Renderer is chosen by `previewKind(for:)` rather than handing everything to
/// Quick Look: source files get the kit's syntax highlighting, which Quick
/// Look's flat monospace rendering cannot match.
struct PreviewPane: View {
    let entry: FileEntry?
    let itemCount: Int

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            if let entry {
                header(entry)
                Divider().opacity(0)  // spacing only — the design forbids rules
                content(for: entry)
            } else {
                AinkradEmptyState(
                    icon: "sidebar.right", title: "No Selection",
                    message: "Select a file to preview it."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(AinkradSpacing.md)
        .frame(width: 300)
    }

    private func header(_ entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(AinkradFontResolver.font(.body, weight: .medium, typography: typo))
                .foregroundStyle(theme.foreground)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(formattedSize(entry.size, isDirectory: entry.isDirectory))
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(0.5))
        }
    }

    @ViewBuilder
    private func content(for entry: FileEntry) -> some View {
        switch previewKind(for: entry) {
        case .code(let language):
            if let text = previewText(at: entry.url) {
                ScrollView { AinkradCodeBlock(text, language: language) }
            } else {
                unavailable
            }

        case .text:
            if let text = previewText(at: entry.url) {
                ScrollView {
                    Text(text)
                        .font(AinkradFontResolver.font(.mono, typography: typo))
                        .foregroundStyle(theme.foreground.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                unavailable
            }

        case .image:
            if let image = NSImage(contentsOf: entry.url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                unavailable
            }

        case .quickLook:
            QuickLookPreview(url: entry.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .directory:
            AinkradEmptyState(
                icon: "folder", title: entry.name,
                message: "\(itemCount) item\(itemCount == 1 ? "" : "s")"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .none:
            unavailable
        }
    }

    private var unavailable: some View {
        AinkradEmptyState(
            icon: "eye.slash", title: "No Preview",
            message: "This file type can't be previewed."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `QLPreviewView` wrapper for the types Quick Look genuinely handles better —
/// PDFs, video, office documents.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        // Guard against redundant reloads: reassigning the same item restarts
        // media playback from zero.
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }
}
