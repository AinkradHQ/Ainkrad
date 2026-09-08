import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

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
            return AnyView(try ScryTextCard(element: element, tokens: tokens).content())
        case .table:
            return AnyView(ScryTableCard(element: element, tokens: tokens))
        case .code:
            return AnyView(ScryCodeCard(element: element, tokens: tokens))
        case .status, .card:
            return AnyView(ScryStatusCard(element: element, tokens: tokens))
        case .image:
            return AnyView(ScryImageCard(element: element, tokens: tokens))
        case .video, .audio:
            return AnyView(ScryMediaCard(element: element, tokens: tokens))
        case .diagram, .chart:
            return AnyView(ScryDiagramView(element: element, tokens: tokens))
        case .unknown:
            return AnyView(ScryStatusCard(element: element, tokens: tokens))
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

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(tokens.danger).frame(width: 7, height: 7).padding(.top, 3)
            Text("Render error: \(message)")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.danger.opacity(0.9))
        }
    }
}
