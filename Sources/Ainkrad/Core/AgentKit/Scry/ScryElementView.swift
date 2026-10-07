import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// A render failure isolated to one element — surfaced as an inline error
/// card rather than propagating and taking down the rest of the canvas.
struct ScryElementRenderError: Error {
    let message: String
}

/// The inline error card, drawn as the kit `AinkradErrorState` and shared by `ScryElementView` (for any kind
/// whose `buildContent()` throws) and `ScryTextCard` (whose markdown parse
/// failure is caught internally so it stays a real `View`, per the uniform
/// `(element:)` dispatcher contract), and by the mermaid host (with
/// its own "Diagram render error" label).
struct ScryErrorCard: View {
    let message: String
    var label = "Render error"

    var body: some View {
        AinkradErrorState(message: "\(label): \(message)")
    }
}

/// Renders one scry element. A failure in any branch degrades to an inline
/// error card; an unknown kind degrades to a placeholder — never a crash,
/// and never takes any other element on the canvas down with it.
@MainActor
struct ScryElementView: View {
    @Environment(\.ainkradSkin) private var skin
    let element: ScryElement
    @Environment(\.ainkradTheme) private var theme

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
            let message =
                (error as? ScryElementRenderError)?.message
                ?? String(describing: error)
            return AnyView(ScryErrorCard(message: message))
        }
    }

    private func buildContent() throws -> AnyView {
        switch element.kind {
        case .text, .markdown:
            return AnyView(ScryTextCard(element: element))
        case .table:
            return AnyView(ScryTableCard(element: element))
        case .code:
            return AnyView(ScryCodeCard(element: element))
        case .status, .card:
            return AnyView(ScryStatusCard(element: element))
        case .image:
            return AnyView(ScryImageCard(element: element))
        case .video, .audio:
            return AnyView(ScryMediaCard(element: element))
        case .diagram, .chart:
            return AnyView(ScryDiagramView(element: element))
        case .unknown:
            return AnyView(ScryStatusCard(element: element))
        }
    }

    // MARK: - card chrome

    /// The kit card (fill, edge, hover brackets and lift), stretched to the
    /// rect `ScryLayout` gave this element.
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                if let title = element.title, !title.isEmpty {
                    Text(title).font(AinkradFont.display(12, weight: .medium)).kerning(0.4)
                        .foregroundStyle(theme.foreground.opacity(skin.opacity.o80))
                }
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
