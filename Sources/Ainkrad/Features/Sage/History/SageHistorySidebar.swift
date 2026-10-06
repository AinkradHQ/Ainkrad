import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

struct SageHistorySidebar: View {
    @Environment(\.ainkradSkin) private var skin
    let store: SageSessionStore
    @Environment(\.ainkradTheme) private var theme
    /// The app's surface opacity for the Sage pane. The sidebar paints the
    /// SAME opacity-tinted base as the chat column so the two read as one
    /// seamless surface at every opacity setting (no separator line, no
    /// mismatched translucency), with only a faint elevation tint to set the
    /// sidebar apart.
    let surfaceOpacity: Double
    var onNewChat: () -> Void
    var onSelect: (UUID) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            header
            AinkradSearchField(text: $query, placeholder: "Search")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                    ForEach(store.results(for: query)) { session in
                        HistoryRow(
                            session: session,
                            isActive: session.id == store.activeID,
                            onSelect: { onSelect(session.id) },
                            onDelete: { store.delete(session.id) })
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(AinkradSpacing.md)
        .frame(width: skin.size.s240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // Same opacity-tinted base as the chat column (`SageRootView`),
            // plus a faint elevation tint. The host renders the blur behind the
            // whole pane, so this only paints the tint.
            ZStack {
                theme.background.opacity(surfaceOpacity)
                theme.surfaceElevated.opacity(skin.opacity.o06)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("HISTORY")
                .font(AinkradFont.display(11, weight: .medium)).kerning(1.5)
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
            Spacer()
            AinkradIconButton(
                systemName: "square.and.pencil", size: 26,
                tooltip: "New chat", action: onNewChat)
        }
    }
}

private struct HistoryRow: View {
    let session: SavedSession
    let isActive: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            AinkradListRow(
                isSelected: isActive,
                onTap: onSelect,
                leading: { EmptyView() },
                title: session.title.isEmpty ? "New chat" : session.title,
                subtitle: session.updatedAt.formatted(.relative(presentation: .named)),
                trailing: { EmptyView() })

            if isHovering {
                AinkradIconButton(
                    systemName: "trash", size: 22,
                    tooltip: "Delete chat", action: onDelete
                )
                .padding(.trailing, AinkradSpacing.xs)
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}

/// Width rule for Sage's history sidebar. In flow it adds `width` to the chat
/// column, whose composer strip needs `chatMinWidth`; below the sum the sidebar
/// overlays the chat column instead, so Sage never exceeds its pane.
enum SageSidebarLayout {
    static let width: CGFloat = 240
    static let chatMinWidth: CGFloat = 360

    static func overlays(paneWidth: CGFloat) -> Bool {
        paneWidth < width + chatMinWidth
    }
}
