import SwiftUI

/// Bounded, inspectable history drawn in one canvas instead of a view per sample.
struct GraphCard: View {
    let history: [Double]
    let metric: Theme.MetricType
    let formatter: (Double) -> String
    var height: CGFloat = 105
    var secondaryHistory: [Double]? = nil
    var secondaryColor: Color? = nil
    var fixedCeiling: Double? = nil
    var title: String = "Activity"
    var primaryLabel: String = "Current"
    var secondaryLabel: String = ""

    @State private var sampleCount = 60
    @State private var frozen: [Double]?
    @State private var frozenSecondary: [Double]?
    @State private var hoverFraction: Double?

    private var accent: Color { Theme.accent(for: metric) }

    var body: some View {
        let values = Array((frozen ?? history).suffix(sampleCount)).map { $0.isFinite ? max(0, $0) : 0 }
        let secondary = Array((frozen != nil ? frozenSecondary ?? [] : secondaryHistory ?? []).suffix(sampleCount))
            .map { $0.isFinite ? max(0, $0) : 0 }
        let ceiling = max(fixedCeiling ?? (max(values.max() ?? 0, secondary.max() ?? 0) * 1.15), 1)
        let index = selectedIndex(count: values.count)
        let current = index.map { values[$0] } ?? values.last ?? 0

        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title.uppercased())
                        .font(Theme.smallCaption).tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach([20, 60], id: \.self) { count in
                            Button {
                                sampleCount = count
                                hoverFraction = nil
                            } label: {
                                Text("\(count)").font(Theme.smallCaption)
                                    .foregroundStyle(sampleCount == count ? Theme.textPrimary : Theme.textSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(sampleCount == count ? accent.opacity(0.22) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Show the latest \(count) samples")
                            .accessibilityLabel("Last \(count) samples")
                            .accessibilityAddTraits(sampleCount == count ? .isSelected : [])
                        }
                    }
                    .background(Theme.insetFill, in: Capsule())
                    Button {
                        if frozen == nil {
                            frozen = history
                            frozenSecondary = secondaryHistory
                        } else {
                            frozen = nil
                            frozenSecondary = nil
                        }
                        hoverFraction = nil
                    } label: {
                        Image(systemName: frozen == nil ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 26, height: 26)
                            .background(accent.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(frozen == nil ? "Freeze this chart to inspect it" : "Resume live chart")
                    .accessibilityLabel(frozen == nil ? "Freeze chart" : "Resume live chart")
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(values.isEmpty ? "—" : formatter(current))
                        .font(Theme.rounded(26, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(index.map { "SAMPLE \($0 + 1)" } ?? (frozen == nil ? "LIVE" : "FROZEN"))
                        .font(Theme.smallCaption)
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                }

                GeometryReader { geo in
                    Canvas { context, size in
                        let plot = CGRect(x: 0, y: 5, width: size.width, height: max(1, size.height - 10))
                        for level in [0.0, 0.5, 1.0] {
                            let y = plot.maxY - plot.height * level
                            var grid = Path()
                            grid.move(to: CGPoint(x: plot.minX, y: y))
                            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                            context.stroke(grid, with: .color(Theme.gridLine), lineWidth: 0.5)
                        }
                        draw(values, color: accent, ceiling: ceiling, plot: plot, context: &context, filled: true)
                        if let color = secondaryColor {
                            draw(secondary, color: color, ceiling: ceiling, plot: plot, context: &context, filled: false)
                        }
                        if let index {
                            let point = point(index: index, value: values[index], count: values.count, ceiling: ceiling, plot: plot)
                            var rule = Path()
                            rule.move(to: CGPoint(x: point.x, y: plot.minY))
                            rule.addLine(to: CGPoint(x: point.x, y: plot.maxY))
                            context.stroke(rule, with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.white))
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoverFraction = min(1, max(0, location.x / max(geo.size.width, 1)))
                        case .ended: hoverFraction = nil
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        Text(formatter(ceiling))
                            .font(Theme.smallCaption).foregroundStyle(Theme.textTertiary)
                            .padding(4).background(Theme.cardFill.opacity(0.9), in: Capsule())
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        if values.isEmpty {
                            Text("Waiting for samples…")
                                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(height: height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(values.count) samples")
                .accessibilityValue(values.isEmpty ? "Waiting for samples" : "\(primaryLabel) \(formatter(current)), average \(formatter(values.reduce(0, +) / Double(values.count))), peak \(formatter(values.max() ?? 0))")

                if !secondary.isEmpty, let color = secondaryColor {
                    HStack {
                        seriesLabel(primaryLabel, value: formatter(current), color: accent)
                        Spacer()
                        let secondaryIndex = index.map { max(0, secondary.count - values.count + $0) }
                        seriesLabel(secondaryLabel, value: formatter(secondaryIndex.flatMap { secondary.indices.contains($0) ? secondary[$0] : nil } ?? secondary.last ?? 0), color: color)
                    }
                }
                HStack {
                    Text("\(values.count) samples")
                    Spacer()
                    Text("Avg \(formatter(values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)))")
                    Text("·")
                    Text("Peak \(formatter(values.max() ?? 0))")
                }
                .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary).monospacedDigit()
            }
        }
    }

    private func selectedIndex(count: Int) -> Int? {
        guard let hoverFraction, count > 0 else { return nil }
        return min(count - 1, max(0, Int((hoverFraction * Double(sampleCount - 1)).rounded()) - (sampleCount - count)))
    }

    private func point(index: Int, value: Double, count: Int, ceiling: Double, plot: CGRect) -> CGPoint {
        CGPoint(x: plot.width * Double(sampleCount - count + index) / Double(sampleCount - 1),
                y: plot.maxY - plot.height * min(1, max(0, value / ceiling)))
    }

    private func draw(_ values: [Double], color: Color, ceiling: Double, plot: CGRect,
                      context: inout GraphicsContext, filled: Bool) {
        guard !values.isEmpty else { return }
        let points = values.enumerated().map { point(index: $0.offset, value: $0.element, count: values.count, ceiling: ceiling, plot: plot) }
        var line = Path()
        line.addLines(points)
        if filled, let first = points.first, let last = points.last {
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
            area.addLine(to: CGPoint(x: first.x, y: plot.maxY))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.34), color.opacity(0.015)]), startPoint: plot.origin, endPoint: CGPoint(x: 0, y: plot.maxY)))
        }
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        if let last = points.last {
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(color))
        }
    }

    private func seriesLabel(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(title) \(value)").font(Theme.smallCaption).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
