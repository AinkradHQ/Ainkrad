import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// `.text` / `.markdown`. Like every other card, this is a plain `View`
/// constructed uniformly as `(element:)` by the dispatcher — a
/// markdown parse failure is caught internally and degrades to the shared
/// `ScryErrorCard`, rather than being discarded by a `try?` that would leave
/// any ordinary use of this view (a preview, a container, another card)
/// silently blank on failure.
@MainActor
struct ScryTextCard: View {
    @Environment(\.ainkradSkin) private var skin
    let element: ScryElement
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        // Evaluated as a plain expression (not inside the `ViewBuilder`
        // closure) so `do`/`catch` is legal here — same pattern as
        // `ScryElementView.safeContent`.
        safeContent
    }

    private var safeContent: AnyView {
        do {
            let attributed = try AttributedString(markdown: element.body)
            return AnyView(
                Text(attributed).font(AinkradFont.display(13))
                    .foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
            )
        } catch {
            let message = "Markdown parse failed: \(error.localizedDescription)"
            return AnyView(ScryErrorCard(message: message))
        }
    }
}

/// `.code` — a syntax-highlighted code block.
@MainActor
struct ScryCodeCard: View {
    let element: ScryElement

    var body: some View {
        AinkradCodeBlock(element.body, language: element.language)
    }
}
