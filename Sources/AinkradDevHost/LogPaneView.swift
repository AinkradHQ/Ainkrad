import AinkradAppKitUI
import SwiftUI

/// Renders `LogTail`'s merged line stream — lifecycle events from
/// `DevHostModel` plus the plugin subsystem's real os_log tail — through the
/// kit's `AinkradLogView`, the same log pane Thrall uses. Kept seamless with
/// the window body per the Cardinal HUD language: a filled background, no
/// separator line above it (the `ValidationBanner` strip above already reads
/// as a distinct region by color, not by a drawn line).
struct LogPaneView: View {
    let logTail: LogTail
    let subsystem: String

    @Environment(\.ainkradSkin) private var skin
    @State private var buffer = AinkradLogBuffer()

    var body: some View {
        AinkradLogView(
            lines: buffer.all, palette: AinkradANSIPalette(skin: skin),
            foreground: skin.color(skin.text.primary)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(skin.color(.palette("black", skin.opacity.o85)))
        .task {
            for await line in logTail.stream(subsystem: subsystem) {
                buffer.append(line + "\n")
            }
        }
    }
}
