import SwiftUI
import AVKit
import AinkradAppKit
import AinkradHostRuntime

/// Hard reference to an AVKit ObjC class so the linker binds AVKit.framework.
/// `import AVKit` alone autolinks only the `_AVKit_SwiftUI` shim used by
/// `VideoPlayer`; that shim's `VideoPlayerView` subclasses `AVPlayerView`, and
/// with AVKit absent from the load commands the Swift runtime aborts the first
/// time a `VideoPlayer` is instantiated. Keep this — it is load-bearing.
private let scryAVKitLinkAnchor: AnyObject.Type = AVPlayerView.self

/// Pure table-body → rows parser (markdown pipe table or CSV). Unit-tested.
/// Detects the separator from the body (`|` wins over `,`), then drops a
/// markdown separator row (all-dash cells) so header/data rows line up.
enum ScryTableParse {
    static func rows(from body: String) -> [[String]] {
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }
        let sep: Character = body.contains("|") ? "|" : ","
        return lines.compactMap { line -> [String]? in
            let cells = line.split(separator: sep, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // Drop a markdown separator row (every cell is all dashes).
            if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 == "-" } }) { return nil }
            return cells
        }
    }
}

/// A render failure isolated to one element — surfaced as an inline error
/// card rather than propagating and taking down the rest of the canvas.
struct ScryElementRenderError: Error {
    let message: String
}

/// Renders one scry element. A failure in any branch degrades to an inline
/// error card; an unknown kind degrades to a placeholder — never a crash,
/// and never takes any other element on the canvas down with it.
@MainActor
struct ScryElementView: View {
    let element: ScryElement
    let tokens: DesignTokens

    var body: some View {
        card {
            safeContent
        }
    }

    // MARK: - error/unknown isolation

    /// Builds the element's content, catching any thrown render failure and
    /// substituting an inline error card. Evaluated as a plain expression
    /// (not inside the `ViewBuilder` closure) so `do`/`catch` is legal here.
    private var safeContent: AnyView {
        do {
            return try buildContent()
        } catch {
            let message = (error as? ScryElementRenderError)?.message
                ?? String(describing: error)
            return AnyView(errorCard(message))
        }
    }

    private func buildContent() throws -> AnyView {
        switch element.kind {
        case .text, .markdown:
            return AnyView(try markdownBody())
        case .table:
            return AnyView(tableBody)
        case .code:
            return AnyView(codeBody)
        case .status:
            return AnyView(statusBody)
        case .card:
            return AnyView(cardBody)
        case .image:
            return AnyView(imageBody)
        case .video:
            return AnyView(videoBody)
        case .audio:
            return AnyView(audioBody)
        case .diagram, .chart:
            return AnyView(ScryDiagramView(element: element, tokens: tokens))
        case .unknown:
            return AnyView(placeholder("Unsupported element type"))
        }
    }

    // MARK: - card chrome

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = element.title, !title.isEmpty {
                Text(title).font(AinkradFont.display(12, weight: .medium)).kerning(0.4)
                    .foregroundStyle(tokens.foreground.opacity(0.8))
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
    }

    // MARK: - per-kind renderers

    private func markdownBody() throws -> some View {
        do {
            let attributed = try AttributedString(markdown: element.body)
            return Text(attributed).font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.9))
        } catch {
            throw ScryElementRenderError(message: "Markdown parse failed: \(error.localizedDescription)")
        }
    }

    private var tableBody: some View {
        let rows = ScryTableParse.rows(from: element.body)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(AinkradFont.mono(11))
                            .foregroundStyle(tokens.foreground.opacity(i == 0 ? 0.9 : 0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var codeBody: some View {
        AinkradCodeBlock(element.body, language: element.language)
    }

    private var statusBody: some View {
        HStack(spacing: 8) {
            Circle().fill(tokens.accentPrimary).frame(width: 7, height: 7)
            Text(element.body).font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
        }
    }

    private var cardBody: some View {
        Text(element.body).font(AinkradFont.display(13))
            .foregroundStyle(tokens.foreground.opacity(0.85))
    }

    @ViewBuilder
    private var imageBody: some View {
        if let nsImage = ScryImageDecoding.dataURLImage(element.body) {
            // `data:` URL (e.g. from `image_generate`) — decode the bytes directly;
            // AsyncImage/URLSession does not load the `data:` scheme.
            Image(nsImage: nsImage).resizable().scaledToFit()
        } else if let url = URL(string: element.body), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { AinkradSpinner(size: 20) }
        } else {
            placeholder("Image unavailable")
        }
    }

    @ViewBuilder
    private var videoBody: some View {
        if let url = URL(string: element.body), url.scheme == "file" || url.scheme?.hasPrefix("http") == true {
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(ChamferShape(cut: AinkradRadius.md))
        } else {
            placeholder("Video unavailable")
        }
    }

    @ViewBuilder
    private var audioBody: some View {
        if let url = URL(string: element.body), url.scheme == "file" || url.scheme?.hasPrefix("http") == true {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 44)
                .clipShape(ChamferShape(cut: AinkradRadius.sm))
        } else {
            placeholder("Audio unavailable")
        }
    }

    private func placeholder(_ message: String) -> some View {
        Text(message).font(AinkradFont.display(12))
            .foregroundStyle(tokens.foreground.opacity(0.4))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(tokens.danger).frame(width: 7, height: 7).padding(.top, 3)
            Text("Render error: \(message)")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.danger.opacity(0.9))
        }
    }
}
