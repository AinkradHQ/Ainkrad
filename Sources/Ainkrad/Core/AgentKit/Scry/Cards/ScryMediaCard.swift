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

/// Validates a media body before it reaches a player. A `file:` URL whose file
/// is gone (a generated clip since cleaned up, or one still being written) used
/// to be handed straight to `AVPlayer`; now it degrades to the placeholder.
enum ScryMediaURL {
    static func playable(_ body: String) -> URL? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "file" {
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return (scheme == "http" || scheme == "https") ? url : nil
    }
}

/// Video and audio. Owns its `AVPlayer` for the card's lifetime — the previous
/// implementation built `AVPlayer(url:)` inside `body`, so every hover,
/// parallax tick and drag frame allocated a fresh player, player item and
/// CoreMedia XPC connection.
@MainActor
struct ScryMediaCard: View {
    let element: ScryElement
    let tokens: DesignTokens

    @State private var player: AVPlayer?

    private var isAudio: Bool { element.kind == .audio }

    var body: some View {
        Group {
            if let player {
                if isAudio {
                    ScryAudioTransport(player: player, tokens: tokens)
                } else {
                    VideoPlayer(player: player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(ChamferShape(cut: AinkradRadius.md))
                }
            } else {
                Text(isAudio ? "Audio unavailable" : "Video unavailable")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            }
        }
        // `id:` keyed on the body, so the player is rebuilt when the URL
        // changes and at no other time.
        .task(id: element.body) {
            player = ScryMediaURL.playable(element.body).map { AVPlayer(url: $0) }
        }
        .onDisappear { player?.pause() }
    }
}

/// Compact audio transport. Audio previously rendered a full `VideoPlayer`
/// squashed to 44pt — a video surface, transport chrome and all, for a sound
/// file.
@MainActor
private struct ScryAudioTransport: View {
    let player: AVPlayer
    let tokens: DesignTokens
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            AinkradIconButton(systemName: isPlaying ? "pause.fill" : "play.fill",
                              size: 22,
                              tooltip: isPlaying ? "Pause" : "Play") {
                if isPlaying { player.pause() } else { player.play() }
                isPlaying.toggle()
            }
            Capsule().fill(tokens.foreground.opacity(0.12)).frame(height: 3)
        }
        .frame(height: 44)
        .onDisappear { player.pause() }
    }
}
