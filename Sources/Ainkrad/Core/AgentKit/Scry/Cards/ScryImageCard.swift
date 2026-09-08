import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// `.image` — a `data:` URL image (e.g. from `image_generate`) or a remote
/// `http(s)` URL loaded via `AsyncImage`.
@MainActor
struct ScryImageCard: View {
    let element: ScryElement
    let tokens: DesignTokens

    var body: some View {
        if let nsImage = ScryImageDecoding.dataURLImage(element.body) {
            // `data:` URL (e.g. from `image_generate`) — decode the bytes directly;
            // AsyncImage/URLSession does not load the `data:` scheme.
            Image(nsImage: nsImage).resizable().scaledToFit()
        } else if let url = URL(string: element.body), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" {
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { AinkradSpinner(size: 20) }
        } else {
            Text("Image unavailable")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.4))
        }
    }
}
