import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// "$x.xxxx" when `cost` is a genuine, known figure; "cost unknown" when it's
/// non-positive — `UsageTracker.record` only accumulates cost when
/// `ModelPriceTable` actually knows the model's price, so a `0` here means
/// "never priced", NEVER a real zero-dollar turn. `BuiltinCommands.usage`
/// (`CommandRegistry.swift`) gates its own dollar figures on the same
/// `cost > 0` convention, so the `/usage` text note and this dashboard never
/// disagree. Pure.
func formattedUsageCost(_ cost: Double) -> String {
    cost > 0 ? "$" + String(format: "%.4f", cost) : "cost unknown"
}

/// "Saved $x.xxxx" for a genuine positive router saving; `nil` (render
/// nothing) for a `nil` or non-positive figure — there's no "$0.0000 saved"
/// line to show when the router either didn't run or had nothing to avoid.
/// Pure.
func formattedRouterSavings(_ savings: Double?) -> String? {
    guard let savings, savings > 0 else { return nil }
    return "Saved $" + String(format: "%.4f", savings)
}

/// The `/usage` dashboard: session + all-time token/cost/savings, plus
/// today's token breakdown, or a first-run empty state before anything is
/// tracked. Built entirely from Cardinal-HUD kit components (`AinkradStatRow`,
/// `AinkradEmptyState`, `AinkradIconGlyph`) — no raw
/// `Text`/`.font(.headline)`/`.foregroundStyle(.secondary)` styling. Presented
/// via `.ainkradModal` from the composer (see `SageComposerBar`'s usage
/// trigger beside the model pill).
struct UsageDashboardView: View {
    let tracker: UsageTracker
    @Environment(\.ainkradTheme) private var theme

    /// True when any usage has ever been tracked. Gated on ALL-TIME totals so a
    /// fresh session with prior history still shows the populated dashboard (its
    /// legitimately-zero session numbers against real all-time figures) — only a
    /// true first-ever run gets the empty state. Pure.
    static func hasUsage(_ cumulative: TokenUsage) -> Bool { cumulative != .zero }

    var body: some View {
        let cumulative = tracker.cumulative()
        let today = tracker.today()

        Group {
            if Self.hasUsage(cumulative.0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                        header
                        sectionPanel(title: "This session") {
                            AinkradStatRow(label: "Input tokens", value: "\(tracker.session.input)")
                            AinkradStatRow(label: "Output tokens", value: "\(tracker.session.output)")
                            AinkradStatRow(label: "Cache read", value: "\(tracker.session.cacheRead)")
                            AinkradStatRow(
                                label: "Cost", value: formattedUsageCost(tracker.sessionCostUSD),
                                status: tracker.sessionCostUSD > 0 ? .neutral : .warning)
                        }
                        sectionPanel(title: "All time") {
                            AinkradStatRow(label: "Input tokens", value: "\(cumulative.0.input)")
                            AinkradStatRow(label: "Output tokens", value: "\(cumulative.0.output)")
                            AinkradStatRow(label: "Cache read", value: "\(cumulative.0.cacheRead)")
                            AinkradStatRow(
                                label: "Cost", value: formattedUsageCost(cumulative.costUSD),
                                status: cumulative.costUSD > 0 ? .neutral : .warning)
                            if let savings = formattedRouterSavings(cumulative.savingsUSD) {
                                AinkradStatRow(label: "Router savings", value: savings, status: .success)
                            }
                        }
                        sectionPanel(title: "Today") {
                            AinkradStatRow(label: "Input tokens", value: "\(today.input)")
                            AinkradStatRow(label: "Output tokens", value: "\(today.output)")
                            AinkradStatRow(label: "Cache read", value: "\(today.cacheRead)")
                        }
                    }
                    .padding(AinkradSpacing.lg)
                }
                // Content-height so the card scrolls only if the sections
                // outgrow the cap — keeps the modal a compact centered card
                // (like Settings/Launcher), never a full-height strip.
                .frame(maxHeight: 460)
            } else {
                // Empty state: header pinned top, the (space-filling) empty
                // treatment centered below within a compact card.
                VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                    header
                    AinkradEmptyState(
                        icon: "gauge.with.dots.needle.67percent",
                        title: "No usage yet",
                        message: "Token counts and cost appear here after your first message.",
                        actionTitle: nil,
                        action: nil
                    )
                }
                .padding(AinkradSpacing.lg)
                .frame(height: 240)
            }
        }
    }

    private var header: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: "gauge.with.dots.needle.67percent", filled: true)
            Text("Usage")
                .font(AinkradFont.display(15, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func sectionPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            Text(title.uppercased())
                .font(AinkradFont.display(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.accentSecondary.opacity(0.85))
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(AinkradSpacing.md)
                .background(ChamferShape(cut: AinkradRadius.md).fill(theme.surfaceElevated.opacity(0.4)))
        }
    }
}
