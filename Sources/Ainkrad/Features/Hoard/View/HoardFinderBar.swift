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
    @Environment(\.ainkradSkin) private var skin

    @FocusState private var fieldFocused: Bool
    @State private var highlighted = 0

    private var hits: [SearchHit] { search.rankedResults }
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if !hits.isEmpty || search.isSearching || !search.queryText.isEmpty {
                resultList
            }
            footer
        }
        .frame(width: skin.size.s560)
        .hudPanelChrome(tokens: tokens)
        .onAppear {
            fieldFocused = true
            highlighted = 0
        }
        .onChange(of: search.queryText) { _, _ in highlighted = 0 }
    }

    /// The Launcher's command field, so the two palettes read as one family;
    /// the leading mark says which palette this is.
    private var field: some View {
        HStack(spacing: AinkradSpacing.md) {
            AinkradCommandField(
                placeholder, text: $search.queryText, focus: $fieldFocused,
                leading: {
                    Image(systemName: search.mode == .jump ? "arrow.turn.down.right" : "magnifyingglass")
                        .font(skin.font(AinkradFontToken(sizeKey: "t13", weight: "semibold", scaled: false)))
                        .foregroundStyle(tokens.color(\.accentSecondary))
                },
                onArrow: { arrow in
                    switch arrow {
                    case .down: return moveHighlight(1)
                    case .up: return moveHighlight(-1)
                    default: return false
                    }
                },
                onSubmit: submitHighlighted,
                onEscape: onClose
            )

            if search.isSearching {
                AinkradSpinner(size: skin.size.s16)
            }
        }
        .padding(.trailing, AinkradSpacing.lg)
    }

    @ViewBuilder
    private var resultList: some View {
        if hits.isEmpty && !search.isSearching && !search.queryText.isEmpty {
            Text("No matches")
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
                .padding(.horizontal, AinkradSpacing.lg)
                .padding(.bottom, AinkradSpacing.md)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: skin.size.s2) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            resultRow(hit, isHighlighted: index == highlighted)
                                .id(hit.id)
                                .onTapGesture { onSubmit(hit) }
                        }
                    }
                    .padding(.horizontal, AinkradSpacing.sm)
                }
                .frame(maxHeight: skin.size.s360)
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
                .foregroundStyle(tokens.color(\.foreground))
                .lineLimit(1)
            Spacer(minLength: AinkradSpacing.md)
            // WHERE it was found is most of the value of a recursive search.
            Text(hit.relativeDirectory)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o45))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(tokens.color(\.accentSecondary).opacity(isHighlighted ? skin.opacity.o12 : 0))
        )
        // The Launcher's targeting brackets on the highlighted row, for the
        // same reason: one selection language across every palette.
        .overlay(
            TargetingBrackets()
                .stroke(tokens.color(\.accentSecondary), lineWidth: isHighlighted ? 1 : 0)
        )
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: AinkradSpacing.md) {
            Text(search.mode == .jump ? "Jump" : "Global search")
                .foregroundStyle(tokens.color(\.accentSecondary))
            if search.didTruncate {
                // Silent truncation would read as "that's everything".
                Text("first \(hits.count) shown — narrow to see more")
            } else if !hits.isEmpty {
                Text("\(hits.count) result\(hits.count == 1 ? "" : "s")")
            }
            Spacer()
            Text("↑↓ move · ⏎ open · esc close")
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o40))
        }
        .font(AinkradFontResolver.font(.caption, typography: typo))
        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o55))
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

    /// `false` with no hits, so the arrow reaches the caret instead.
    private func moveHighlight(_ delta: Int) -> Bool {
        guard !hits.isEmpty else { return false }
        highlighted = min(max(0, highlighted + delta), hits.count - 1)
        return true
    }

    private func submitHighlighted() {
        guard hits.indices.contains(highlighted) else { return }
        onSubmit(hits[highlighted])
    }
}
