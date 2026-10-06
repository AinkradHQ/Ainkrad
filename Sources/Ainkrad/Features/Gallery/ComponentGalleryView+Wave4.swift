#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Wave 4: navigation and feedback.
extension ComponentGalleryView {
    var wave4Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Navigation · Feedback", subtitle: "Wave-4 Cardinal HUD components")

            wave4NavigationRow
            wave4CommandNavRow
            wave4StatusSpinnerRow
            wave4BannerToastRow
            wave4TooltipPopoverRow
            wave4ConfirmDialogRow
            wave4StateViewsRow
        }
    }

    private var wave4Tabs: [String] { ["Overview", "Details", "History"] }
    private var wave4Breadcrumb: [String] { ["Ainkrad", "Projects", "Component Gallery"] }
    private var wave4CommandMenuItems: [(icon: String, label: String)] {
        [
            ("terminal", "Terminal"),
            ("gearshape", "Settings"),
            ("square.stack.3d.up", "Workspaces"),
            ("bolt.fill", "Actions"),
        ]
    }
    private var wave4NavListItems: [String] { ["Dashboard", "Repositories", "Pull Requests", "Settings"] }

    private var wave4NavigationRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Tabs, Breadcrumb, Pagination")
            AinkradTabs(tabs: wave4Tabs, selection: $wave4TabsSelection) { $0 }
            AinkradBreadcrumb(items: wave4Breadcrumb)
            AinkradPagination(page: $wave4PaginationPage, pageCount: 5)
        }
    }

    private var wave4CommandNavRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Command Menu, Nav List")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradCommandMenu(
                    items: wave4CommandMenuItems.map(\.label),
                    selection: $wave4CommandMenuSelection,
                    icon: { label in wave4CommandMenuItems.first { $0.label == label }?.icon ?? "questionmark" },
                    label: { $0 }
                )
                .frame(width: 180)
                AinkradNavList(
                    items: wave4NavListItems,
                    selection: $wave4NavListSelection,
                    icon: { _ in "chevron.right" },
                    label: { $0 }
                )
                .frame(width: 200)
            }
        }
    }

    private var wave4StatusSpinnerRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Status Bar (accent & status kinds), Spinner")
            HStack(spacing: AinkradSpacing.lg) {
                VStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                    AinkradStatusBar(value: 0.75, kind: .accent)
                    AinkradStatusBar(value: 0.4, kind: .status(.warning))
                    AinkradStatusBar(value: 0.9, kind: .status(.danger))
                }
                .frame(width: 160)
                AinkradSpinner()
            }
        }
    }

    private var wave4BannerToastRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Banner (per status), Toast")
            VStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                ForEach(AinkradStatus.allCases, id: \.self) { status in
                    AinkradBanner(message: "\(String(describing: status).capitalized) banner message", status: status)
                }
            }
            FireToastButton()
        }
    }

    private var wave4TooltipPopoverRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Tooltip, Popover")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradButton(title: "Hover me", style: .ghost, action: {})
                    .ainkradTooltip("This is a Cardinal HUD tooltip")
                AinkradButton(title: "Show Popover", style: .secondary) {
                    wave4PopoverPresented = true
                }
                .ainkradPopover(isPresented: $wave4PopoverPresented) {
                    Text("Popover content")
                        .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground)
                }
            }
        }
    }

    private var wave4ConfirmDialogRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Confirm Dialog (default & destructive) — centers in the gallery app surface")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradButton(title: "Confirm…", style: .secondary) {
                    wave4ConfirmDialogPresented = true
                }
                AinkradButton(title: "Delete…", style: .danger) {
                    wave4DestructiveConfirmDialogPresented = true
                }
            }
        }
    }

    private var wave4StateViewsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Restyled: Empty State (with & without action), Error State, Loading State")
            HStack(spacing: AinkradSpacing.md) {
                AinkradEmptyState(
                    icon: "tray", title: "Nothing here", message: "No items yet.",
                    actionTitle: "Add Item", action: {}
                )
                .frame(height: 180)
                AinkradEmptyState(icon: "tray", title: "Nothing here", message: "No items yet.")
                    .frame(height: 180)
                AinkradErrorState(message: "Something went wrong.", retryTitle: "Retry", retry: {})
                    .frame(height: 180)
                AinkradLoadingState(label: "Loading…")
                    .frame(height: 180)
            }
        }
    }
}
#endif
