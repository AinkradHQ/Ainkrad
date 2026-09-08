import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Live Scry: agent-rendered cards, auto-arranged. Cards flow newest-first
/// into columns; dragging or resizing one records an override in the store and
/// that card floats above the flow, which re-packs around it.
///
/// No pointer parallax: it depended on `z` (now gone) and re-animated every
/// card on every pointer move. Hover lift and shadow remain.
@MainActor
struct ScryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let store: ScryStore

    // Fails open: `nil` means "no offset delivered yet, so cull nothing."
    // The scroll preference is the one mechanism here nobody has verified at
    // runtime — if it never fires, degrading to "builds too much" is far
    // safer than silently dropping every card below ~2 viewports.
    @State private var visibleTop: CGFloat?

    var body: some View {
        let tokens = environment.themeManager.tokens
        GeometryReader { proxy in
            let elements = store.model.elements
            let overrides = store.overrides
            let frames = ScryLayout.frames(for: elements, in: proxy.size,
                                           overrides: overrides)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Flow cards.
                    ForEach(elements) { element in
                        if let rect = frames[element.id],
                           isVisible(rect, viewportHeight: proxy.size.height) {
                            ScryCard(element: element, store: store, tokens: tokens,
                                     rect: rect, isFloating: false,
                                     containerSize: proxy.size,
                                     reduceMotion: reduceMotion)
                        }
                    }
                    // Floating (user-placed) cards, above the flow.
                    ForEach(elements) { element in
                        if let rect = overrides[element.id],
                           isVisible(rect, viewportHeight: proxy.size.height) {
                            ScryCard(element: element, store: store, tokens: tokens,
                                     rect: rect, isFloating: true,
                                     containerSize: proxy.size,
                                     reduceMotion: reduceMotion)
                        }
                    }
                }
                .background(
                    GeometryReader { g in
                        Color.clear.preference(
                            key: ScryScrollOffsetKey.self,
                            value: -g.frame(in: .named("scry-scroll")).minY)
                    })
                .frame(height: max(proxy.size.height,
                                   ScryLayout.contentHeight(for: elements, in: proxy.size,
                                                            overrides: overrides)),
                       alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: "scry-scroll")
            .onPreferenceChange(ScryScrollOffsetKey.self) { visibleTop = $0 }
            .overlay {
                if elements.isEmpty { emptyState(tokens: tokens) }
            }
        }
    }

    /// Whether a card's rect is near enough the viewport to be worth building.
    /// Fails open: with no offset yet, everything is considered visible.
    private func isVisible(_ rect: ScryRect, viewportHeight: CGFloat) -> Bool {
        guard let visibleTop else { return true }
        let margin = viewportHeight
        let top = visibleTop - margin
        let bottom = visibleTop + viewportHeight + margin
        return CGFloat(rect.y + rect.height) >= top && CGFloat(rect.y) <= bottom
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

/// Scroll offset of the Scry content, used to cull offscreen cards.
private struct ScryScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// One draggable/resizable card wrapping a `ScryElementView`.
@MainActor
private struct ScryCard: View {
    let element: ScryElement
    let store: ScryStore
    let tokens: DesignTokens
    let rect: ScryRect
    let isFloating: Bool
    let containerSize: CGSize
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

    /// The rect actually rendered: the incoming `rect` (flow or override),
    /// overlaid with any in-flight drag/resize preview. `rect` itself never
    /// changes mid-gesture (the store isn't written to until `.onEnded`), so
    /// it stays a stable anchor for the whole gesture.
    private var previewRect: ScryRect {
        var r = rect
        r.x += dragPreviewOffset.width
        r.y += dragPreviewOffset.height
        if let size = resizePreviewSize {
            r.width = size.width
            r.height = size.height
        }
        return r
    }

    /// A dropped card must stay reachable: origin can't go negative (that
    /// clips the card off the top/left with no way to scroll back to it),
    /// and it can't be dropped so far right that no sliver of it remains
    /// inside the container's width.
    private func clamped(_ r: ScryRect) -> ScryRect {
        var r = r
        let minVisible: Double = 40
        r.x = max(0, min(r.x, max(0, Double(containerSize.width) - minVisible)))
        r.y = max(0, r.y)
        return r
    }

    var body: some View {
        ScryElementView(element: element, tokens: tokens)
            .overlay(alignment: .topTrailing) { if isHovering { controls } }
            .overlay(alignment: .bottomTrailing) { if isHovering { resizeHandle } }
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .shadow(color: tokens.accentSecondary.opacity(isHovering ? 0.18 : 0.08),
                    radius: isHovering ? 12 : 6)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .gesture(
                DragGesture()
                    .updating($dragStart) { _, state, _ in
                        if state == nil { state = rect }
                    }
                    .onChanged { v in
                        dragPreviewOffset = v.translation
                    }
                    .onEnded { v in
                        let base = dragStart ?? rect
                        var newRect = base
                        newRect.x = base.x + Double(v.translation.width)
                        newRect.y = base.y + Double(v.translation.height)
                        store.setOverride(id: element.id, clamped(newRect))
                        dragPreviewOffset = .zero
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
                        if state == nil { state = rect }
                    }
                    .onChanged { v in
                        let base = resizeStart ?? rect
                        resizePreviewSize = CGSize(width: max(160, base.width + v.translation.width),
                                                    height: max(100, base.height + v.translation.height))
                    }
                    .onEnded { v in
                        let base = resizeStart ?? rect
                        let width = max(160, base.width + Double(v.translation.width))
                        let height = max(100, base.height + Double(v.translation.height))
                        var newRect = base
                        newRect.width = width
                        newRect.height = height
                        store.setOverride(id: element.id, newRect)
                        resizePreviewSize = nil
                    }
            )
    }
}
