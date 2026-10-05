import AinkradAppKit
import AinkradAppKitUI
import SwiftUI

/// Breadcrumb that becomes a path editor on ⌘L. Two modes rather than an
/// always-editable field: the breadcrumb is the common case and clicking a
/// segment must navigate, not place a cursor.
struct HoardBreadcrumbBar: View {
    @Bindable var tab: HoardTab
    let fileSystem: any FileSystemServing

    @Binding var isEditing: Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var components: [(name: String, url: URL)] {
        breadcrumbComponents(for: tab.currentDirectory)
    }

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            historyControls
            Group {
                if isEditing { editor } else { breadcrumb }
            }
        }
        .padding(.horizontal, HoardColumnMetrics.headerInset)
        .padding(.vertical, AinkradSpacing.sm)
        .onChange(of: isEditing) { _, editing in
            if editing {
                draft = tab.currentDirectory.path
                fieldFocused = true
            }
        }
    }

    /// Back/forward beside the path, where a browser puts them. Disabled
    /// states are dimmed rather than hidden, so the controls don't jump.
    private var historyControls: some View {
        HStack(spacing: 2) {
            historyButton("chevron.left", enabled: tab.canGoBack) { tab.goBack() }
            historyButton("chevron.right", enabled: tab.canGoForward) { tab.goForward() }
        }
    }

    private func historyButton(
        _ symbol: String, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.foreground.opacity(enabled ? 0.7 : 0.25))
                .frame(width: 20, height: 20)
                .background(ChamferShape(cut: 4).fill(theme.foreground.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: enabled)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(Array(components.enumerated()), id: \.offset) { index, part in
                    BreadcrumbSegment(
                        title: part.name,
                        isLast: index == components.count - 1,
                        action: { tab.navigate(to: part.url) }
                    )
                    if index < components.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(theme.foreground.opacity(0.25))
                    }
                }
            }
            // Anchored right: with a deep path the TAIL is what matters, and
            // a left-anchored scroll view would show you "/Users/…" forever.
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
        // Double-click empty space to edit — a single click would fight the
        // segment buttons for the same pixels.
        .onTapGesture(count: 2) { isEditing = true }
    }

    private var editor: some View {
        HStack(spacing: AinkradSpacing.xs) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(theme.foreground.opacity(0.35))
            TextField("Path", text: $draft)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.mono, typography: typo))
                .focused($fieldFocused)
                .onSubmit(commit)
                .onExitCommand { isEditing = false }
                .onKeyPress(.tab) {
                    if let completed = completePath(
                        draft, using: fileSystem,
                        home: fileSystem.homeDirectory)
                    {
                        draft = completed
                    }
                    return .handled
                }
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, 4)
        .background(ChamferShape(cut: 4).fill(theme.foreground.opacity(0.07)))
    }

    private func commit() {
        let path = expandTilde(draft, home: fileSystem.homeDirectory)
        let url = URL(fileURLWithPath: path)
        // Typing a FILE path navigates to its enclosing folder — the useful
        // interpretation of pasting a path you copied from somewhere else.
        tab.navigate(to: fileSystem.isDirectory(url) ? url : url.deletingLastPathComponent())
        isEditing = false
    }
}

/// One breadcrumb segment. The trailing segment — where you actually are —
/// reads at full strength; ancestors are dimmed until hovered, so the bar
/// tells you your location at a glance instead of being a wall of equal text.
private struct BreadcrumbSegment: View {
    let title: String
    let isLast: Bool
    let action: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(
                    AinkradFontResolver.font(
                        .caption, weight: isLast ? .medium : .regular,
                        typography: typo)
                )
                .foregroundStyle(theme.foreground.opacity(isLast ? 0.95 : 0.55))
                .lineLimit(1)
                .padding(.horizontal, AinkradSpacing.xs)
                .padding(.vertical, 3)
                .background(
                    ChamferShape(cut: 3)
                        .fill(hovering ? theme.foreground.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
