import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// One parsed chart data point: a label and its non-negative value.
struct ScryChartBar: Equatable, Sendable {
    let label: String
    let value: Double
}

/// Pure CSV `label,value` → bar parser, built on `ScryTableParse`. A row
/// that isn't exactly two cells, has an empty label, or whose value isn't a
/// finite non-negative number is skipped rather than failing the whole
/// chart — one bad line shouldn't blank every other bar. If every row is
/// skipped the result is empty and the caller falls back to a preformatted
/// card. Unit-tested.
enum ScryChartParse {
    static func bars(from body: String) -> [ScryChartBar] {
        ScryTableParse.rows(from: body).compactMap { row -> ScryChartBar? in
            guard row.count == 2 else { return nil }
            let label = row[0]
            guard !label.isEmpty, let value = Double(row[1]), value.isFinite, value >= 0 else {
                return nil
            }
            return ScryChartBar(label: label, value: value)
        }
    }
}

/// Shape-drawn HUD bar chart — zero native controls, just `Capsule`/`Text`
/// laid out with SwiftUI. Bar length is proportional to `value / maxValue`;
/// a zero-value row still renders (as the minimum-width capsule) so it
/// stays visible rather than vanishing.
@MainActor
struct ScryChartView: View {
    @Environment(\.ainkradSkin) private var skin
    let bars: [ScryChartBar]
    @Environment(\.ainkradTheme) private var theme

    private var maxValue: Double {
        max(bars.map(\.value).max() ?? 0, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                row(index: index, bar: bar)
            }
        }
    }

    private func row(index: Int, bar: ScryChartBar) -> some View {
        HStack(spacing: skin.spacing.sm) {
            Text(bar.label)
                .font(AinkradFont.mono(10))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o70))
                .frame(width: 64, alignment: .leading)  // design-lint: allow frame-literal chart geometry, label column width is data layout
                .lineLimit(1)
            GeometryReader { geo in
                Capsule()
                    .fill(barColor(for: index))
                    .frame(
                        width: max(2, geo.size.width * CGFloat(bar.value / maxValue)),
                        height: 14
                    )
            }
            .frame(height: 14)  // design-lint: allow frame-literal chart geometry, bar thickness is data layout
            Text(formatted(bar.value))
                .font(AinkradFont.mono(10))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
                .frame(width: 44, alignment: .trailing)  // design-lint: allow frame-literal chart geometry, value column width is data layout
        }
    }

    private func barColor(for index: Int) -> Color {
        index.isMultiple(of: 2) ? theme.accentPrimary : theme.accentSecondary
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
