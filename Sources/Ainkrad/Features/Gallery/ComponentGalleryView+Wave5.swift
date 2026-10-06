#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Wave 5: data and overlays.
extension ComponentGalleryView {
    var wave5Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Data · Overlays", subtitle: "Wave-5 Cardinal HUD components")

            wave5ListRowsColumn
            wave5StatRowsColumn
            wave5IconGlyphRow
            wave5DataTableSample
            wave5MeterRow
            wave5StackedStatusBarRow
            basicShellRow
            wave5AppTileRow
            wave5CodeBlockSample
            wave5LogViewSample
            wave5OverlayTriggersRow
        }
    }

    private var wave5ListRowsColumn: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("List Row (selected, trailing badge, right-click first row for a CUSTOM context menu)")
            VStack(spacing: AinkradSpacing.xs) {
                AinkradListRow(
                    isSelected: wave5ListRowSelection == "cpu-core-0",
                    onTap: { wave5ListRowSelection = "cpu-core-0" },
                    leading: { AinkradIconGlyph(systemName: "cpu", filled: true) },
                    title: "cpu-core-0",
                    subtitle: "4 threads · 3.2 GHz",
                    trailing: { AinkradBadge(text: "Active", status: .success) }
                )
                .ainkradContextMenu([
                    AinkradMenuItem(title: "Inspect", systemName: "magnifyingglass", action: {}),
                    AinkradMenuItem(title: "Restart", systemName: "arrow.clockwise", action: {}),
                    AinkradMenuItem(title: "Terminate", systemName: "xmark.octagon", isDestructive: true, action: {}),
                ])

                AinkradListRow(
                    isSelected: wave5ListRowSelection == "gpu-0",
                    onTap: { wave5ListRowSelection = "gpu-0" },
                    leading: { AinkradIconGlyph(systemName: "cpu.fill") },
                    title: "gpu-0",
                    subtitle: "Metal · 16 GB",
                    trailing: { AinkradBadge(text: "Idle", status: .neutral) }
                )

                AinkradListRow(
                    leading: { AinkradIconGlyph(systemName: "network") },
                    title: "net-0",
                    trailing: { AinkradBadge(text: "Warning", status: .warning) }
                )
            }
        }
    }

    private var wave5StatRowsColumn: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Stat Row (per status)")
            VStack(spacing: 2) {
                AinkradStatRow(label: "Uptime", value: "14d 6h", status: .neutral)
                AinkradStatRow(label: "Load Avg", value: "0.42", status: .success)
                AinkradStatRow(label: "Temp", value: "78°C", status: .warning)
            }
        }
    }

    private var wave5IconGlyphRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Icon Glyph (outline & filled)")
            HStack(spacing: AinkradSpacing.md) {
                AinkradIconGlyph(systemName: "bolt")
                AinkradIconGlyph(systemName: "bolt.fill", filled: true)
                AinkradIconGlyph(systemName: "shield")
                AinkradIconGlyph(systemName: "shield.fill", filled: true)
                AinkradIconGlyph(systemName: "flame", size: 20)
                AinkradIconGlyph(systemName: "flame.fill", size: 20, filled: true)
            }
        }
    }

    private var wave5TableRows: [GalleryProcessRow] {
        [
            GalleryProcessRow(id: "1", name: "agentd", cpu: "12.4", status: "Running"),
            GalleryProcessRow(id: "2", name: "terminal-host", cpu: "3.1", status: "Running"),
            GalleryProcessRow(id: "3", name: "indexer", cpu: "44.8", status: "Busy"),
            GalleryProcessRow(id: "4", name: "sync-worker", cpu: "0.2", status: "Idle"),
            GalleryProcessRow(id: "5", name: "watcher", cpu: "1.6", status: "Idle"),
        ]
    }

    private var wave5TableColumns: [AinkradTableColumn<GalleryProcessRow>] {
        [
            AinkradTableColumn(id: "name", title: "Process", cell: { $0.name }),
            AinkradTableColumn(id: "cpu", title: "CPU %", alignment: .trailing, cell: { $0.cpu }),
            .accessory(id: "status", title: "Status", alignment: .leading) { row in
                AinkradBadge(
                    text: row.status,
                    status: row.status == "Running" ? .success : row.status == "Busy" ? .warning : .neutral)
            },
            .accessory(id: "actions") { _ in
                AinkradIconButton(systemName: "stop.fill", size: 22, tooltip: "Stop") {}
            },
        ]
    }

    private var wave5DataTableSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Data Table (sort by header; click, ⌘-click or ⇧-click rows to select)")
            AinkradDataTable(
                rows: wave5TableRows, columns: wave5TableColumns, sort: $wave5TableSort,
                selection: $wave5TableSelection)
        }
    }

    private var wave5MeterRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Meter")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradMeter(value: 0.42, label: "CPU")
                AinkradMeter(value: 0.86, label: "Disk", kind: .status(.warning))
            }
        }
    }

    /// The three cases the component exists for: a mixed set, a single failure
    /// in a large one (2 pt minimum, and it must not be clipped), and empty.
    private var wave5StackedStatusBarSamples: [(String, [AinkradStatusRun])] {
        [
            (
                "19 running · 28 exited · 1 created",
                [
                    .init(count: 19, status: .success), .init(count: 28, status: .warning),
                    .init(count: 1, status: .neutral),
                ]
            ),
            (
                "1,000 running · 1 dead",
                [.init(count: 1_000, status: .success), .init(count: 1, status: .danger)]
            ),
            (
                "90 running · 2 exited · 3 restarting",
                [
                    .init(count: 3, status: .danger), .init(count: 2, status: .warning),
                    .init(count: 90, status: .success),
                ]
            ),
            ("empty — the track still draws", []),
        ]
    }

    private var wave5StackedStatusBarRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Stacked Status Bar (severity order, worst last; a single failure keeps 2 pt)")
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                ForEach(Array(wave5StackedStatusBarSamples.enumerated()), id: \.offset) { _, sample in
                    HStack(spacing: AinkradSpacing.md) {
                        AinkradStackedStatusBar(runs: sample.1).frame(width: 64)
                        AinkradStackedStatusBar(runs: sample.1).frame(width: 220)
                        AinkradCaption(sample.0)
                    }
                }
            }
        }
    }

    /// Generation 11's Basic Mode surface, shown in both the shapes the nine
    /// apps need: with primary actions (Git Mage, Thrall, Leyline) and without
    /// (Lore, Raven, Sage, where the content carries its own).
    ///
    /// Both the pane mode and its setter are seeded locally so the switch is
    /// live here — the Gallery is not a host pane, so without this it would
    /// render as "Simplify" and do nothing.
    private var basicShellRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Basic Shell (the shared basic-mode surface; the switch is live)")
            HStack(alignment: .top, spacing: AinkradSpacing.md) {
                AinkradBasicShell(
                    icon: "wand.and.stars",
                    title: "Ainkrad",
                    subtitle: "development · 3 behind"
                ) {
                    AinkradButton(title: "Fetch", style: .secondary) {}
                    AinkradButton(title: "Pull", style: .primary) {}
                } content: {
                    AinkradCaption("the one thing you came for")
                }
                .frame(width: 320, height: 120)
                .ainkradPanel()

                AinkradBasicShell(
                    icon: "doc.text", title: "roadmap.md",
                    subtitle: "Docs/Plans"
                ) {
                    AinkradCaption("a document, actions in the content")
                }
                .frame(width: 280, height: 120)
                .ainkradPanel()
            }
            .environment(\.ainkradPaneMode, galleryPaneMode)
            .environment(\.ainkradSetPaneMode) { galleryPaneMode = $0 }
        }
    }

    private var wave5AppTileRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("App Tile")
            HStack(spacing: AinkradSpacing.md) {
                AinkradAppTile(symbol: "terminal", title: "Terminal")
                AinkradAppTile(symbol: "gearshape", title: "Settings", isSelected: true)
            }
        }
    }

    private var wave5CodeBlockSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Code Block")
            AinkradCodeBlock(
                """
                func meterFraction(value: Double, total: Double) -> Double {
                    guard total > 0 else { return 0 }
                    return max(0, min(value / total, 1))
                }
                """,
                language: "swift"
            )
        }
    }

    /// Seed lines covering what the palette maps: plain stdout, 8-colour and
    /// bold codes, dim text, uncoloured stderr, and a source name long enough
    /// to be truncated in the source column.
    static func sampleLog() -> AinkradLogBuffer {
        var log = AinkradLogBuffer()
        log.append("listening on :8080\n", source: "api")
        log.append("\u{1B}[32m✓\u{1B}[0m migrations applied (12)\n", source: "api")
        log.append("\u{1B}[33mWARN\u{1B}[0m slow query 812 ms: SELECT * FROM jobs\n", source: "api")
        log.append("\u{1B}[1;31mERROR\u{1B}[0m connection refused: db:5432\n", source: "runtime-head-hunter")
        log.append("retrying in 5s\n", stream: .stderr, source: "runtime-head-hunter")
        log.append("\u{1B}[2mdebug: pool size 16\u{1B}[0m\n", source: "api")
        log.append("\u{1B}[36mGET\u{1B}[0m /health 200 3 ms\n", source: "api")
        return log
    }

    private var wave5LogViewSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Log View (ticks every 2 s; turn Follow off and scroll up to read; select, ⌘F, copy)")
            HStack(spacing: AinkradSpacing.lg) {
                HStack(spacing: AinkradSpacing.sm) {
                    AinkradToggle(isOn: $wave5LogFollowing)
                    AinkradCaption("Follow")
                }
                HStack(spacing: AinkradSpacing.sm) {
                    AinkradToggle(isOn: $wave5LogShowsSource)
                    AinkradCaption("Source column")
                }
            }
            AinkradLogView(
                lines: wave5Log.all,
                palette: AinkradANSIPalette(theme: galleryTokens, statusColors: galleryStatusColors),
                foreground: galleryTokens.foreground,
                showsSourcePrefix: wave5LogShowsSource,
                isFollowing: wave5LogFollowing
            )
            .frame(height: 180)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(galleryTokens.surface.opacity(0.9)))
            .task {
                // A live tail, so follow mode has something to follow.
                var tick = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    tick += 1
                    wave5Log.append("worker tick \(tick) ok\n", source: "sync-worker")
                }
            }
        }
    }

    private var wave5OverlayTriggersRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Modal, Sheet, Drawer — scoped to the gallery app surface (attached at panel root)")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradButton(title: "Show Modal", style: .secondary) { wave5ModalPresented = true }
                AinkradButton(title: "Show Sheet", style: .secondary) { wave5SheetPresented = true }
                AinkradButton(title: "Show Drawer", style: .secondary) { wave5DrawerPresented = true }
            }
        }
    }


    func wave5OverlaySampleContent(title: String, message: String, dismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            Text(title)
                .font(AinkradFontResolver.font(.headline, weight: .semibold, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground)
            Text(message)
                .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.8))
            AinkradButton(title: "Close", style: .secondary, action: dismiss)
        }
    }
}


/// Reads `\.ainkradToastCenter` from its OWN position in the view tree (a
/// genuine descendant of wherever `.ainkradToastHost()` is mounted), rather
/// than at `ComponentGalleryView`'s level. A `@Environment` read only sees
/// environment values set by a view's ANCESTORS — `.ainkradToastHost()` is
/// mounted on `panel`, a child `ComponentGalleryView` builds in its own
/// `body`, so `ComponentGalleryView` reading the environment on itself would
/// still see the pre-host default, never the center the host renders from.
/// A separate child view like this one, nested inside that same subtree, is
/// the correct place to read it.
/// Sample row for the Wave-5 `AinkradDataTable` demo — a fake process
/// readout with a few text columns, matching the table's v1 text-cell-only
/// contract.
private struct GalleryProcessRow: Identifiable {
    let id: String
    let name: String
    let cpu: String
    let status: String
}

struct FireToastButton: View {
    @Environment(\.ainkradToastCenter) private var center

    var body: some View {
        AinkradButton(title: "Fire Toast", style: .secondary) {
            center.show("Sample toast message", status: .success)
        }
    }
}
#endif
