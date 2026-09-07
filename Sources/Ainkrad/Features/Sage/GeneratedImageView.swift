import SwiftUI
import AVKit
import AinkradAppKit
import AinkradHostRuntime
import AppKit

/// A generated image rendered inline in the transcript with hover / right-click
/// actions: open full-screen, copy, download. Decodes the `data:` URL once and
/// renders nothing if the payload can't be decoded. The full-screen presentation
/// is delegated to the window root via `onOpen` (a card is inside a scroll view
/// and can't host a window-covering overlay itself).
struct GeneratedImageView: View {
    let dataURL: String
    let tokens: DesignTokens
    var onOpen: ((NSImage) -> Void)? = nil

    @State private var isHovering = false
    @State private var copied = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var decoded: (image: NSImage, data: Data, ext: String)? {
        guard let data = ScryImageDecoding.base64Payload(dataURL), let image = NSImage(data: data) else { return nil }
        return (image, data, Self.fileExtension(for: dataURL))
    }

    var body: some View {
        if let d = decoded {
            Image(nsImage: d.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 320, alignment: .leading)
                .clipShape(ChamferShape(cut: AinkradRadius.md))
                .overlay(ChamferShape(cut: AinkradRadius.md).stroke(tokens.accentSecondary.opacity(0.22), lineWidth: 1))
                .overlay(alignment: .topTrailing) { actionBar(d).padding(6) }
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .onTapGesture { onOpen?(d.image) }
                // HUD menu, not the AppKit one — see BlockView's note.
                .ainkradContextMenu([
                    AinkradMenuItem(title: "Open Full Screen",
                                    systemName: "arrow.up.left.and.arrow.down.right") { onOpen?(d.image) },
                    AinkradMenuItem(title: "Copy Image", systemName: "doc.on.doc") { copy(d.image) },
                    AinkradMenuItem(title: "Download…", systemName: "square.and.arrow.down") {
                        download(d.data, ext: d.ext)
                    },
                ])
                .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
        }
    }

    private func actionBar(_ d: (image: NSImage, data: Data, ext: String)) -> some View {
        HStack(spacing: 2) {
            AinkradIconButton(systemName: "arrow.up.left.and.arrow.down.right", size: 22, tooltip: "Open full screen") { onOpen?(d.image) }
            AinkradIconButton(systemName: copied ? "checkmark" : "doc.on.doc", size: 22, tooltip: "Copy image") { copy(d.image) }
            AinkradIconButton(systemName: "square.and.arrow.down", size: 22, tooltip: "Download") { download(d.data, ext: d.ext) }
        }
        .padding(3)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.background.opacity(0.7)))
        .opacity(isHovering ? 0.95 : 0)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func download(_ data: Data, ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "generated-image.\(ext)"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                Log.app.error("Failed to write \(data.count, privacy: .public) bytes to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// File extension for the image, derived from the `data:` URL's MIME. Pure
    /// and unit-tested.
    static func fileExtension(for dataURL: String) -> String {
        if dataURL.hasPrefix("data:image/jpeg") { return "jpg" }
        if dataURL.hasPrefix("data:image/gif") { return "gif" }
        if dataURL.hasPrefix("data:image/webp") { return "webp" }
        return "png"
    }
}

/// A generated video rendered inline in the transcript with an inline player and
/// hover / right-click actions: open full-screen, download, copy (the file).
/// Renders nothing if the URL is undecodable.
struct GeneratedVideoView: View {
    let urlString: String
    let tokens: DesignTokens
    var onOpen: ((URL) -> Void)? = nil

    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var url: URL? { URL(string: urlString) }

    var body: some View {
        if let url {
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: 360, maxHeight: 240, alignment: .leading)
                .clipShape(ChamferShape(cut: AinkradRadius.md))
                .overlay(ChamferShape(cut: AinkradRadius.md).stroke(tokens.accentSecondary.opacity(0.22), lineWidth: 1))
                .overlay(alignment: .topTrailing) { actionBar(url).padding(6) }
                .onHover { isHovering = $0 }
                .ainkradContextMenu([
                    AinkradMenuItem(title: "Open Full Screen",
                                    systemName: "arrow.up.left.and.arrow.down.right") { onOpen?(url) },
                    AinkradMenuItem(title: "Copy File", systemName: "doc.on.doc") { copy(url) },
                    AinkradMenuItem(title: "Download…", systemName: "square.and.arrow.down") { download(url) },
                ])
        }
    }

    private func actionBar(_ url: URL) -> some View {
        HStack(spacing: 2) {
            AinkradIconButton(systemName: "arrow.up.left.and.arrow.down.right", size: 22, tooltip: "Open full screen") { onOpen?(url) }
            AinkradIconButton(systemName: "square.and.arrow.down", size: 22, tooltip: "Download") { download(url) }
        }
        .padding(3)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.background.opacity(0.7)))
        .opacity(isHovering ? 0.95 : 0)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    private func download(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "generated-video.\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                Log.app.error("Failed to copy \(url.lastPathComponent, privacy: .public) to \(dest.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// A generated speech clip rendered inline in the transcript with a full audio
/// transport: play/pause, a seek scrubber, elapsed / total time, playback speed,
/// and download. Renders nothing if the URL is undecodable.
struct GeneratedAudioView: View {
    let urlString: String
    let title: String
    let tokens: DesignTokens

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var rateIndex = 0

    private let rates: [Float] = [1.0, 1.25, 1.5, 2.0]
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    private var url: URL? { URL(string: urlString) }

    var body: some View {
        if let url {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AinkradIconButton(systemName: isPlaying ? "pause.fill" : "play.fill", size: 26,
                                      tooltip: isPlaying ? "Pause" : "Play") { toggle(url) }
                    Text(timeString(current)).font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.6)).monospacedDigit()
                    AinkradSlider(value: Binding(
                        get: { current },
                        set: { current = $0; player?.currentTime = $0 }), in: 0...max(duration, 0.01))
                    Text(timeString(duration)).font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.6)).monospacedDigit()
                }
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 11))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.7))
                    Text(title).font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.75))
                    Spacer(minLength: 8)
                    AinkradIconButton(systemName: "speedometer", size: 20, tooltip: "Playback speed") { cycleRate() }
                    Text("\(speedLabel)").font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.7)).monospacedDigit()
                    AinkradIconButton(systemName: "square.and.arrow.down", size: 20, tooltip: "Download") { download(url) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: 360, alignment: .leading)
            .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
            .overlay(ChamferShape(cut: AinkradRadius.md).stroke(tokens.accentSecondary.opacity(0.22), lineWidth: 1))
            .onAppear { ensurePlayer(url) }
            .onReceive(ticker) { _ in
                guard isPlaying, let p = player else { return }
                current = p.currentTime
                if !p.isPlaying { isPlaying = false; current = 0 }
            }
        }
    }

    private var speedLabel: String {
        let r = rates[rateIndex]
        return r == r.rounded() ? "\(Int(r))x" : String(format: "%.2gx", r)
    }

    private func ensurePlayer(_ url: URL) {
        guard player == nil else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.rate = rates[rateIndex]
        duration = player?.duration ?? 0
    }

    private func toggle(_ url: URL) {
        ensurePlayer(url)
        guard let p = player else { return }
        if isPlaying { p.pause(); isPlaying = false }
        else { p.rate = rates[rateIndex]; p.play(); isPlaying = true }
    }

    private func cycleRate() {
        rateIndex = (rateIndex + 1) % rates.count
        player?.rate = rates[rateIndex]
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func download(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "speech.\(url.pathExtension.isEmpty ? "caf" : url.pathExtension)"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                Log.app.error("Failed to copy \(url.lastPathComponent, privacy: .public) to \(dest.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Full-window lightbox for a generated video: dimmed backdrop, the player scaled
/// to fit, click-outside or Esc to dismiss.
struct VideoLightboxView: View {
    let url: URL
    let tokens: DesignTokens
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.85)).ignoresSafeArea().onTapGesture { onDismiss() }
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .padding(40)
                .overlay(alignment: .topTrailing) {
                    AinkradIconButton(systemName: "xmark", size: 26, tooltip: "Close") { onDismiss() }
                        .padding(20)
                }
        }
        .onExitCommand { onDismiss() }
        .transition(.opacity)
    }
}

/// Full-window lightbox for a generated image: dimmed backdrop, the image scaled
/// to fit, click-anywhere or Esc to dismiss. Presented by `SageRootView` as
/// a window-covering overlay.
struct ImageLightboxView: View {
    let image: NSImage
    let tokens: DesignTokens
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.8))
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(40)
                .overlay(alignment: .topTrailing) {
                    AinkradIconButton(systemName: "xmark", size: 26, tooltip: "Close") { onDismiss() }
                        .padding(20)
                }
        }
        .onExitCommand { onDismiss() } // Esc
        .transition(.opacity)
    }
}
