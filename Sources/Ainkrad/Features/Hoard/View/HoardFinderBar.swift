import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// The ⌘F search and ⌘P jump palette.
///
/// Uses the host's `hudPanelChrome` — the same finish as the Launcher,
/// Settings and Workspace Overview — rather than a hand-rolled background, so
/// it reads as part of Ainkrad instead of a foreign panel. That includes the
/// settings-driven overlay opacity and blur, so it follows whatever the user
/// has configured for every other overlay.
struct HoardFinderBar: View {
    @Bindable var search: HoardSearchStore
    let iconSize: CGFloat
    let onSubmit: (SearchHit) -> Void
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo

    @FocusState private var fieldFocused: Bool
    @State private var highlighted = 0

    private var hits: [SearchHit] { search.rankedResults }
    private var tokens: DesignTokens { environment.themeManager.tokens }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if !hits.isEmpty || search.isSearching || !search.queryText.isEmpty {
                resultList
            }
            footer
        }
        .frame(width: 560)
        .hudPanelChrome(tokens: tokens)
        .onAppear {
            fieldFocused = true
            highlighted = 0
        }
        .onChange(of: search.queryText) { _, _ in highlighted = 0 }
    }

    private var field: some View {
        HStack(spacing: AinkradSpacing.md) {
            // The Launcher's chevron mark, so the two palettes read as one
            // family.
            Image(systemName: search.mode == .jump ? "arrow.turn.down.right" : "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.accentSecondary)

            TextField(placeholder, text: $search.queryText)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.headline, typography: typo))
                .foregroundStyle(tokens.foreground)
                .focused($fieldFocused)
                .onSubmit(submitHighlighted)
                .onExitCommand(perform: onClose)
                .onKeyPress(.downArrow) { moveHighlight(1) }
                .onKeyPress(.upArrow) { moveHighlight(-1) }

            if search.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.vertical, AinkradSpacing.md)
    }

    @ViewBuilder
    private var resultList: some View {
        if hits.isEmpty && !search.isSearching && !search.queryText.isEmpty {
            Text("No matches")
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .padding(.horizontal, AinkradSpacing.lg)
                .padding(.bottom, AinkradSpacing.md)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            resultRow(hit, isHighlighted: index == highlighted)
                                .id(hit.id)
                                .onTapGesture { onSubmit(hit) }
                        }
                    }
                    .padding(.horizontal, AinkradSpacing.sm)
                }
                .frame(maxHeight: 360)
                .onChange(of: highlighted) { _, index in
                    guard hits.indices.contains(index) else { return }
                    proxy.scrollTo(hits[index].id, anchor: nil)
                }
            }
        }
    }

    private func resultRow(_ hit: SearchHit, isHighlighted: Bool) -> some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: iconName(for: hit.entry), size: iconSize)
                .frame(width: iconSize + 6)
            Text(hit.entry.name)
                .font(AinkradFontResolver.font(.body, typography: typo))
                .foregroundStyle(tokens.foreground)
                .lineLimit(1)
            Spacer(minLength: AinkradSpacing.md)
            // WHERE it was found is most of the value of a recursive search.
            Text(hit.relativeDirectory)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(tokens.foreground.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(tokens.accentSecondary.opacity(isHighlighted ? 0.12 : 0))
        )
        // The Launcher's targeting brackets on the highlighted row, for the
        // same reason: one selection language across every palette.
        .overlay(
            TargetingBrackets()
                .stroke(tokens.accentSecondary, lineWidth: isHighlighted ? 1 : 0)
        )
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: AinkradSpacing.md) {
            Text(search.mode == .jump ? "Jump" : "Global search")
                .foregroundStyle(tokens.accentSecondary)
            if search.didTruncate {
                // Silent truncation would read as "that's everything".
                Text("first \(hits.count) shown — narrow to see more")
            } else if !hits.isEmpty {
                Text("\(hits.count) result\(hits.count == 1 ? "" : "s")")
            }
            Spacer()
            Text("↑↓ move · ⏎ open · esc close")
                .foregroundStyle(tokens.foreground.opacity(0.4))
        }
        .font(AinkradFontResolver.font(.caption, typography: typo))
        .foregroundStyle(tokens.foreground.opacity(0.55))
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.vertical, AinkradSpacing.sm)
    }

    private var placeholder: String {
        // No "press Return" — it searches as you type. And ⌘F is GLOBAL now,
        // so the copy must not still claim it is scoped to a folder.
        switch search.mode {
        case .jump: return "Jump to a file…"
        case .globalSearch: return "Search everywhere…"
        case nil: return "Search…"
        }
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        guard !hits.isEmpty else { return .ignored }
        highlighted = min(max(0, highlighted + delta), hits.count - 1)
        return .handled
    }

    private func submitHighlighted() {
        guard hits.indices.contains(highlighted) else { return }
        onSubmit(hits[highlighted])
    }
}
