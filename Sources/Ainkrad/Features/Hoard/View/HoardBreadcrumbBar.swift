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
    @Environment(\.ainkradSkin) private var skin

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
        HStack(spacing: skin.size.s2) {
            historyButton("chevron.left", tooltip: "Back", enabled: tab.canGoBack) { tab.goBack() }
            historyButton("chevron.right", tooltip: "Forward", enabled: tab.canGoForward) { tab.goForward() }
        }
    }

    private func historyButton(
        _ symbol: String, tooltip: String, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        AinkradIconButton(systemName: symbol, size: skin.size.s20, tooltip: tooltip, action: action)
        .disabled(!enabled)
        .opacity(enabled ? 1 : skin.opacity.o35)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: enabled)
    }

    /// The kit's trail: the current folder reads as the accent crumb, every
    /// ancestor navigates.
    private var breadcrumb: some View {
        let parts = components
        return ScrollView(.horizontal, showsIndicators: false) {
            AinkradBreadcrumb(items: parts.map(\.name)) { index in
                tab.navigate(to: parts[index].url)
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
                .font(skin.font(AinkradFontToken(sizeKey: "t9", scaled: false)))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o35))
            TextField("Path", text: $draft)  // design-lint: allow raw-control kit gap, focus binding
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
        .padding(.vertical, skin.size.s4)
        .background(ChamferShape(cut: skin.cut.c4).fill(theme.foreground.opacity(skin.opacity.o07)))
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
