import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// `.text` / `.markdown`. `content()` is the throwing render path — it is
/// what `ScryElementView.buildContent()` calls so a markdown parse failure
/// surfaces as `ScryElementRenderError` and degrades to an inline error card
/// there, rather than being swallowed here. `body` (the `View` requirement,
/// which cannot itself throw) falls back to a blank view on failure and is
/// not the path the dispatcher uses.
@MainActor
struct ScryTextCard: View {
    let element: ScryElement
    let tokens: DesignTokens

    var body: some View {
        if let view = try? content() {
            AnyView(view)
        } else {
            AnyView(EmptyView())
        }
    }

    func content() throws -> some View {
        do {
            let attributed = try AttributedString(markdown: element.body)
            return Text(attributed).font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.9))
        } catch {
            throw ScryElementRenderError(message: "Markdown parse failed: \(error.localizedDescription)")
        }
    }
}

/// `.code` — a syntax-highlighted code block.
@MainActor
struct ScryCodeCard: View {
    let element: ScryElement
    let tokens: DesignTokens

    var body: some View {
        AinkradCodeBlock(element.body, language: element.language)
    }
}
