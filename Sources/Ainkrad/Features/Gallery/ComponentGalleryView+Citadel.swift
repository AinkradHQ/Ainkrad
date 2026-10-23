#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal,padding-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Citadel kit (AppKit #119–#122): charts, the transcript's tool card and
/// chat bubble, the ten Citadel components and the animated agent figure.
extension ComponentGalleryView {
    struct ChainLink: Identifiable, Equatable {
        let id: String
        let harness: String
        let model: String
        let account: String
    }

    static let sampleChain = [
        ChainLink(id: "a", harness: "Codex", model: "gpt-5.5", account: "account: codex-pro · effort high"),
        ChainLink(id: "b", harness: "Claude", model: "Opus 5.5", account: "account: pool (least used, healthy)"),
        ChainLink(id: "c", harness: "OpenCode", model: "qwen3-coder", account: "unpriced · last resort"),
    ]

    // MARK: - Charts

    var chartsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Charts", subtitle: "Line, bar, sparkline and scatter, styled by the skin")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradBarChart(
                    title: "Per day", bars: Self.perDaySpend,
                    threshold: AinkradChartThreshold(value: 48, label: "daily warn $48"), format: { "$\($0)" }
                ).frame(height: 150)
                AinkradLineChart(
                    title: "Burndown", series: Self.burndown,
                    axisLabels: [
                        AinkradChartAxisLabel(x: 0, text: "Oct 13"), AinkradChartAxisLabel(x: 6, text: "today"),
                        AinkradChartAxisLabel(x: 10, text: "Oct 24"),
                    ]
                ).frame(height: 150)
            }
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradLineChart(
                    title: "Spend today", series: [Self.line("Spend", Self.spendToday)],
                    threshold: AinkradChartThreshold(value: 24, label: "warn $24"), fillsArea: true
                ).frame(height: 120)
                AinkradScatterChart(
                    title: "Cycle and lead time",
                    series: [
                        Self.line("Cycle", [1.2, 1.8, 0.9, 2.2, 1.6, 2.6, 1.9, 1.1, 2.4, 1.0, 2.8, 1.7]),
                        Self.line(
                            "Lead", [2.5, 3.6, 1.2, 4.6, 3.9, 5.6, 3.2, 2.3, 4.1, 2.4, 6.1, 3.0], tone: .accentTertiary),
                    ],
                    threshold: AinkradChartThreshold(value: 3.6, label: "p85 3.6d")
                ).frame(height: 120)
            }
            HStack(spacing: AinkradSpacing.lg) {
                AinkradSparkline(
                    title: "Spend today", values: Self.spendToday,
                    threshold: AinkradChartThreshold(value: 24, label: "warn")
                ).frame(width: 160, height: 40)
                AinkradLineChart(title: "Burndown", series: []).frame(width: 320, height: 80)
            }
        }
    }

    // MARK: - Transcript

    var transcriptSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Transcript", subtitle: "Tool card in every status, chat bubble")
            AinkradToolCard(
                name: "Read", argument: "citadel/crates/citadel-server/src/stream.rs", status: .succeeded,
                result: .summary("412 lines"))
            AinkradToolCard(
                name: "Edit", argument: "citadel/crates/citadel-server/src/stream.rs", status: .succeeded,
                result: .counts(added: 38, removed: 6), isInitiallyExpanded: true
            ) {
                AinkradCodeBlock(".filter(|e| e.seq >= last_seen.next())", language: "rust")
            }
            AinkradToolCard(
                name: "Bash", argument: "cargo add tokio-tungstenite@0.26 --features rustls", status: .waiting,
                footnote: "Network access to crates.io is outside this project's sandbox policy.")
            AinkradToolCard(
                name: "Bash", argument: "cargo test -p citadel-server", status: .failed, result: .summary("exit 101"),
                note: "Rewritten by a hook from: cargo test")
            AinkradToolCard(name: "Grep", argument: "replay_from", status: .running) {
                EmptyView()
            } accessory: { state in
                Text(state.isWide ? "↗ Open in Forge" : "↗ Forge")
            }
            AinkradChatBubble(
                text: "Draft the launch post for Ainkrad 1.0. Lead with the **OS, not web app** idea.",
                author: "You", meta: "09:40")
            AinkradChatBubble(text: "Match this layout", attachments: ["mockup.png", "notes.png"])
            AinkradChatBubble(
                text: "First draft is up — 860 words. I left two marked placeholders in `draft.md`.",
                role: .agent, author: "Quill", meta: "Writer · 10:02"
            ) {
                AinkradAgentFigure(name: "Quill", state: .success, harness: .claude, size: 24)
            }
        }
    }

    // MARK: - Citadel components

    var citadelSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Citadel", subtitle: "Budgets, agents, proposals and scoped settings")
            HStack(alignment: .top, spacing: AinkradSpacing.xl) {
                VStack(spacing: 18) {
                    AinkradBudgetBar(label: "Company · October", value: 412, limit: 900)
                    AinkradBudgetBar(label: "Issue MKT-8", value: 4.2, limit: 5)
                    AinkradBudgetBar(label: "Agent Flint", value: 40, limit: 40)
                    AinkradBudgetBar(
                        label: "claude-personal", value: 82, limit: 100, warnFraction: nil, showsHardLimit: false,
                        tone: .accentViolet)
                    AinkradBudgetBar(label: "Sprint CIT S4", value: 35, limit: 60, warnFraction: 0.7, isThick: true)
                }
                .frame(width: 300)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        AinkradRedactedChip("GITHUB_TOKEN", reason: "Redacted before it was written to the log")
                        AinkradRedactedChip("run token")
                    }
                    HStack(spacing: 10) {
                        AinkradPointsPill(points: $citadelPoints)
                        AinkradPointsPill(points: .constant(nil), estimator: "Toma")
                        AinkradPointsPill(points: 13)
                        AinkradPointsPill(points: nil)
                    }
                    AinkradSkeletonRow()
                    AinkradSkeletonRow(widthFraction: 0.7)
                    AinkradSkeletonRow(widthFraction: 0.85, showsAvatar: false)
                }
                .frame(width: 320)
            }
            HStack(alignment: .top, spacing: AinkradSpacing.xl) {
                AinkradWorkspaceSwitcher(
                    workspaces: Self.citadelCompanies, selection: $citadelWorkspace,
                    subtitle: "Citadel · 2 other companies", header: "Companies on citadel.ainkrad.io",
                    footnote: "Accounts, runners and cost are per company.", onNew: {}
                )
                .frame(width: 260)
                AinkradWorkspaceMenu(
                    workspaces: Self.citadelCompanies, selection: $citadelWorkspace,
                    header: "Companies on citadel.ainkrad.io",
                    footnote: "Accounts, runners and cost are per company.", onNew: {})
            }
            HStack(alignment: .top, spacing: AinkradSpacing.xl) {
                AinkradQuestionCard(
                    asker: "Kestrel (Dev)", issueKey: "CIT-62", context: "estimating S5", age: "4m",
                    question: "Use a **.p8 token key** (never expires) or a **.p12 certificate** per app?",
                    replies: [".p8 token key", ".p12 certificate", "Ask Toma"],
                    route: "Your answer goes to Kestrel on CIT-62 and wakes it"
                ) {
                    AinkradAgentFigure(name: "Kestrel", state: .thinking, harness: .codex, size: 18)
                }
                .frame(width: 368)
                AinkradProposalCard(
                    author: "Toma (Lead)", title: "Lint command", tag: "citadel", oldValue: "cargo clippy",
                    newValue: "cargo clippy && cargo deny check", reason: "CIT-74 shipped a yanked dependency.",
                    onAccept: {}, onReject: {}
                ) {
                    AinkradAgentFigure(name: "Toma", state: .idle, palette: .ultraviolet, harness: .claude, size: 24)
                }
                .frame(width: 368)
            }
            HStack(alignment: .top, spacing: AinkradSpacing.xl) {
                HStack(spacing: 10) {
                    AinkradFileThumbnail(
                        name: "qa-report-cit-61.md", typeLabel: "report · md", agent: "Sable",
                        references: ["CIT-61"], isSelected: true
                    ) {
                        Self.docPreview
                    } avatar: {
                        AinkradAgentFigure(name: "Sable", state: .rest, palette: .aurora, size: 18)
                    }
                    AinkradFileThumbnail(
                        name: "lease-expired.png", typeLabel: "png · 1440×900", agent: "Sable",
                        references: ["CIT-61"], detail: "run #428"
                    ) {
                        Self.docPreview
                    } avatar: {
                        AinkradAgentFigure(name: "Sable", state: .rest, palette: .aurora, size: 18)
                    }
                }
                .frame(width: 368)
                AinkradReorderList(items: $citadelChain, isNumbered: true, current: "a", dimmed: ["c"]) { link in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            AinkradBadge(text: link.harness)
                            Text(link.model)
                        }
                        AinkradCaption(link.account)
                    }
                }
                .frame(width: 340)
            }
            VStack(spacing: 10) {
                AinkradScopedValue(
                    label: "Stall after", bounds: "1–120 min", value: $citadelStall,
                    scope: .overridden(at: "project", inheritedValue: "company 15 min"), onReset: {})
                AinkradScopedValue(
                    label: "WIP per agent", bounds: "1–10", value: .constant("3"), scope: .inherited(from: "company"))
            }
            .frame(width: 448)
            AinkradCaption("Agent figure (every state, 64 · 32 · 24 pt)")
            HStack(alignment: .bottom, spacing: AinkradSpacing.lg) {
                ForEach(AinkradFigureState.allCases, id: \.self) { state in
                    VStack(spacing: 6) {
                        AinkradAgentFigure(name: "Mira", state: state, harness: .claude, size: 64)
                        HStack(alignment: .bottom, spacing: 4) {
                            AinkradAgentFigure(name: "Mira", state: state, harness: .claude, size: 32)
                            AinkradAgentFigure(name: "Mira", state: state, harness: .claude, size: 24)
                        }
                        AinkradCaption(state.rawValue)
                    }
                }
            }
        }
    }

    // MARK: - Sample data

    private static let perDaySpend: [AinkradChartBar] = [
        (14, 1, 8), (18, 0, 9), (22, 1, 8), (17, 0, 11), (9, 0, 5), (3, 0, 2),
        (24, 2, 10), (28, 0, 12), (26, 1, 10), (30, 0, 14), (27, 1, 10), (6, 0, 4),
    ].enumerated().map { day, spend in
        AinkradChartBar(
            label: "Oct \(day + 1)",
            segments: [
                AinkradBarSegment(name: "Priced", value: spend.0, tone: .accentSecondary),
                AinkradBarSegment(name: "Unpriced", value: spend.1, tone: .warning),
                AinkradBarSegment(name: "Subscription", value: spend.2, tone: .accentViolet),
            ])
    }

    private static let spendToday = [2.0, 3, 4, 5.5, 6, 9, 10.5, 12, 14, 15, 16.5, 18.4]

    private static var burndown: [AinkradChartSeries] {
        [
            line("Ideal", [34, 30.6, 27.2, 23.8, 20.4, 17, 13.6, 10.2, 6.8, 3.4, 0], tone: .muted, dashed: true),
            line("Actual", [34, 34, 37, 33, 29, 24, 19]),
        ]
    }

    private static func line(
        _ name: String, _ ys: [Double], tone: AinkradChartTone = .accentSecondary, dashed: Bool = false
    ) -> AinkradChartSeries {
        AinkradChartSeries(
            name: name, points: ys.enumerated().map { AinkradChartPoint(x: Double($0.offset), y: $0.element) },
            tone: tone, isDashed: dashed)
    }

    private static let citadelCompanies = [
        AinkradWorkspace(id: "aink", name: "Ainkrad", kind: .own, detail: "18 agents · 3 projects", needsYou: 8),
        AinkradWorkspace(
            id: "amai", name: "AutomotiveAi", kind: .client, tint: .green, detail: "9 agents · 2 projects",
            needsYou: 2),
        AinkradWorkspace(id: "opt", name: "Optimus", kind: .client, tint: .purple, detail: "6 agents · 1 project"),
    ]

    /// The mockups' document preview: a heading bar and text lines.
    private static var docPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(.white.opacity(0.45)).frame(width: 90, height: 6)
            Capsule().fill(.white.opacity(0.18)).frame(height: 4)
            Capsule().fill(.white.opacity(0.18)).frame(width: 110, height: 4)
            Capsule().fill(.cyan.opacity(0.3)).frame(width: 80, height: 4)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
    }
}
#endif
