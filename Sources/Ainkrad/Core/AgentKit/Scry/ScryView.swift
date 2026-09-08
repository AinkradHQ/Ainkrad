import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Live Scry: agent-rendered elements as movable/resizable layered HUD
/// cards with hover + parallax. The user can rearrange/pin/dismiss; layout
/// persists per session via `ScryStore`. Reconstructable from the transcript.
@MainActor
struct ScryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let store: ScryStore

    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        let tokens = environment.themeManager.tokens
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hoverPoint = p }
                    }

                if store.model.elements.isEmpty {
                    emptyState(tokens: tokens)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                ForEach(store.model.ordered) { element in
                    ScryCard(element: element, store: store, tokens: tokens,
                               parallax: parallax(for: element, in: proxy.size),
                               reduceMotion: reduceMotion)
                        .zIndex(Double(element.z))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Small pointer-driven parallax per card (deeper z drifts less).
    private func parallax(for element: ScryElement, in size: CGSize) -> CGSize {
        guard !reduceMotion, size.width > 0 else { return .zero }
        let dx = (hoverPoint.x / size.width - 0.5) * 8
        let dy = (hoverPoint.y / size.height - 0.5) * 8
        let depth = 1.0 / Double(max(1, element.z + 1))
        return CGSize(width: dx * depth, height: dy * depth)
    }

    private func emptyState(tokens: DesignTokens) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed").font(.system(size: 26))
                .foregroundStyle(tokens.foreground.opacity(0.25))
            Text("The assistant will lay results out here")
                .font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One draggable/resizable card wrapping a `ScryElementView`.
@MainActor
private struct ScryCard: View {
    let element: ScryElement
    let store: ScryStore
    let tokens: DesignTokens
    let parallax: CGSize
    let reduceMotion: Bool
    @State private var isHovering = false
    @GestureState private var dragStart: ScryRect?
    @GestureState private var resizeStart: ScryRect?
    // Perf fix (I2/M1): live-drag/resize preview state ONLY, kept even though
    // `ScryStore` is in-memory now — committing on every `DragGesture.
    // onChanged` tick would still re-layout the whole surface per pixel of
    // movement. These hold the in-flight visual delta; the store is
    // committed exactly once, in `.onEnded`.
    @State private var dragPreviewOffset: CGSize = .zero
    @State private var resizePreviewSize: CGSize?
    @State private var hasBroughtToFrontThisDrag = false

    /// The rect actually rendered: the committed `element.rect`, overlaid with
    /// any in-flight drag/resize preview. `element.rect` itself never changes
    /// mid-gesture (the store isn't written to until `.onEnded`), so it stays
    /// a stable anchor for the whole gesture.
    private var previewRect: ScryRect {
        var r = element.rect
        r.x += dragPreviewOffset.width
        r.y += dragPreviewOffset.height
        if let size = resizePreviewSize {
            r.width = size.width
            r.height = size.height
        }
        return r
    }

    var body: some View {
        ScryElementView(element: element, tokens: tokens)
            .overlay(alignment: .topTrailing) { if isHovering { controls } }
            .overlay(alignment: .bottomTrailing) { if isHovering { resizeHandle } }
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .offset(parallax)
            .shadow(color: tokens.accentSecondary.opacity(isHovering ? 0.18 : 0.08),
                    radius: isHovering ? 12 : 6)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: parallax)
            .gesture(
                DragGesture()
                    .updating($dragStart) { _, state, _ in
                        if state == nil { state = element.rect }
                    }
                    .onChanged { v in
                        if !hasBroughtToFrontThisDrag {
                            let top = store.model.nextZ
                            store.update(id: element.id) { $0.z = top }
                            hasBroughtToFrontThisDrag = true
                        }
                        dragPreviewOffset = v.translation
                    }
                    .onEnded { v in
                        let base = dragStart ?? element.rect
                        store.update(id: element.id) {
                            $0.rect.x = base.x + Double(v.translation.width)
                            $0.rect.y = base.y + Double(v.translation.height)
                        }
                        dragPreviewOffset = .zero
                        hasBroughtToFrontThisDrag = false
                    }
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.x, y: previewRect.y)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            AinkradIconButton(systemName: element.pinned ? "pin.fill" : "pin", size: 20,
                               tooltip: element.pinned ? "Unpin" : "Pin") {
                store.setPinned(id: element.id, !element.pinned)
            }
            AinkradIconButton(systemName: "xmark", size: 20, tooltip: "Dismiss") {
                store.remove(id: element.id)
            }
        }
        .padding(6)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right").font(.system(size: 10))
            .foregroundStyle(tokens.foreground.opacity(0.4)).padding(4)
            .gesture(
                DragGesture()
                    .updating($resizeStart) { _, state, _ in
                        if state == nil { state = element.rect }
                    }
                    .onChanged { v in
                        let base = resizeStart ?? element.rect
                        resizePreviewSize = CGSize(width: max(160, base.width + v.translation.width),
                                                    height: max(100, base.height + v.translation.height))
                    }
                    .onEnded { v in
                        let base = resizeStart ?? element.rect
                        let width = max(160, base.width + Double(v.translation.width))
                        let height = max(100, base.height + Double(v.translation.height))
                        store.update(id: element.id) {
                            $0.rect.width = width
                            $0.rect.height = height
                        }
                        resizePreviewSize = nil
                    }
            )
    }
}
