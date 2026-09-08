import SwiftUI
import AVKit
import Combine
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

    @State private var current: (url: URL, player: AVPlayer)?
    @State private var hasResolved = false
    @State private var isPlaying = false
    @State private var statusObservation: NSKeyValueObservation?

    private var player: AVPlayer? { current?.player }
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
            } else if hasResolved {
                // `.task` has actually run and found nothing playable — a
                // genuine failure, not just "hasn't resolved yet".
                Text(isAudio ? "Audio unavailable" : "Video unavailable")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            } else {
                // `.task` runs after the first render, so without this branch
                // "unavailable" would flash for one confident, wrong frame
                // before resolution has even been attempted.
                Color.clear
            }
        }
        // `id:` keyed on the body, so the player is rebuilt when the URL
        // changes and at no other time.
        .task(id: element.body) {
            hasResolved = false
            current = MediaPlayerOwnership.resolve(
                current: current,
                url: ScryMediaURL.playable(element.body),
                make: { AVPlayer(url: $0) })
            hasResolved = true
            observePlaying()
        }
        .onDisappear {
            player?.pause()
            statusObservation?.invalidate()
            statusObservation = nil
        }
        // Reported up so `ScryView` can exempt a still-playing card from
        // scroll culling — culling removes the card from the hierarchy,
        // which would otherwise tear down this `@State` player mid-playback.
        .preference(key: ScryPlayingCardsKey.self, value: isPlaying ? [element.id] : [])
    }

    /// KVO on the player's `timeControlStatus`, re-armed whenever the player
    /// itself changes (a new URL resolved).
    private func observePlaying() {
        statusObservation?.invalidate()
        guard let player else { isPlaying = false; return }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { observedPlayer, _ in
            let playing = observedPlayer.timeControlStatus == .playing
            Task { @MainActor in isPlaying = playing }
        }
    }
}

/// Drives an audio transport's play/pause state, elapsed time and duration
/// from the real `AVPlayer`, rather than a hand-toggled `@State var` that can
/// desync from it (e.g. when the item plays to the end on its own). All
/// mutation happens hopped onto the main actor, since AVFoundation's
/// callbacks are not actor-isolated.
@MainActor
private final class ScryAudioPlayerObserver: ObservableObject, @unchecked Sendable {
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0

    private let player: AVPlayer
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?

    init(player: AVPlayer) {
        self.player = player
        durationSeconds = Self.finiteSeconds(player.currentItem?.duration) ?? 0

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedSeconds = time.seconds
                if let duration = Self.finiteSeconds(self.player.currentItem?.duration) {
                    self.durationSeconds = duration
                }
            }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            let playing = observedPlayer.timeControlStatus == .playing
            Task { @MainActor in
                self?.isPlaying = playing
            }
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    /// Seeks to `fraction` (0...1) of the known duration and updates the
    /// displayed elapsed time immediately, ahead of the next periodic tick.
    func seek(toFraction fraction: Double) {
        guard durationSeconds > 0 else { return }
        let target = fraction * durationSeconds
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsedSeconds = target
    }

    func teardown() {
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        timeObserverToken = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player.pause()
    }

    private static func finiteSeconds(_ time: CMTime?) -> Double? {
        guard let time, time.seconds.isFinite else { return nil }
        return time.seconds
    }
}

/// Compact audio transport. Audio previously rendered a full `VideoPlayer`
/// squashed to 44pt — a video surface, transport chrome and all, for a sound
/// file. The play/pause icon and the scrubber now reflect the real player:
/// icon state comes from `timeControlStatus` (not a hand-toggled flag that
/// can desync when the item finishes on its own), and the capsule is a
/// draggable position backed by a periodic time observer and `seek(to:)`,
/// with an elapsed/duration label — not a decorative bar.
@MainActor
private struct ScryAudioTransport: View {
    let player: AVPlayer
    let tokens: DesignTokens

    @StateObject private var observer: ScryAudioPlayerObserver
    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    init(player: AVPlayer, tokens: DesignTokens) {
        self.player = player
        self.tokens = tokens
        _observer = StateObject(wrappedValue: ScryAudioPlayerObserver(player: player))
    }

    private var progressFraction: Double {
        guard observer.durationSeconds > 0 else { return 0 }
        return isDragging ? dragFraction : min(max(observer.elapsedSeconds / observer.durationSeconds, 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            AinkradIconButton(systemName: observer.isPlaying ? "pause.fill" : "play.fill",
                              size: 22,
                              tooltip: observer.isPlaying ? "Pause" : "Play") {
                observer.togglePlayPause()
            }
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tokens.foreground.opacity(0.12))
                        Capsule().fill(tokens.accentPrimary.opacity(0.85))
                            .frame(width: max(0, geo.size.width * progressFraction))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard geo.size.width > 0 else { return }
                                isDragging = true
                                dragFraction = min(max(value.location.x / geo.size.width, 0), 1)
                            }
                            .onEnded { _ in
                                observer.seek(toFraction: dragFraction)
                                isDragging = false
                            }
                    )
                }
                .frame(height: 3)
                Text(timeLabel)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
        .frame(height: 44)
        .onDisappear { observer.teardown() }
    }

    private var timeLabel: String {
        "\(Self.format(isDragging ? dragFraction * observer.durationSeconds : observer.elapsedSeconds)) / \(Self.format(observer.durationSeconds))"
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
