import SwiftUI

/// A rolling history bar-chart with dashed gridlines and floating value labels.
struct GraphCard: View {
    let history: [Double]
    let metric: Theme.MetricType
    let formatter: (Double) -> String
    var height: CGFloat = 150
    var secondaryHistory: [Double]? = nil
    var secondaryColor: Color? = nil

    private let levels: [Double] = [1.0, 0.75, 0.5, 0.25]

    private var ceiling: Double {
        let primary = history.max() ?? 0
        let secondary = secondaryHistory?.max() ?? 0
        let m = max(primary, secondary)
        return m > 0 ? m * 1.05 : 1
    }

    private var accent: Color { Theme.accent(for: metric) }

    var body: some View {
        GlassCard(padding: 14) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [accent.opacity(0.10), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // Secondary series (e.g. upload) rendered behind primary.
                    if let secondaryHistory, let secondaryColor {
                        barStack(
                            values: secondaryHistory,
                            gradient: LinearGradient(
                                colors: [secondaryColor.opacity(0.25), secondaryColor.opacity(0.7)],
                                startPoint: .bottom, endPoint: .top
                            ),
                            glow: secondaryColor,
                            width: geo.size.width,
                            height: geo.size.height
                        )
                        .opacity(0.85)
                    }

                    barStack(
                        values: history,
                        gradient: Theme.barGradient(for: metric),
                        glow: accent,
                        width: geo.size.width,
                        height: geo.size.height
                    )

                    ForEach(levels, id: \.self) { level in
                        let y = geo.size.height * CGFloat(1 - level)
                        Path { path in
                            path.move(to: CGPoint(x: 58, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Theme.gridLine, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                        Text(formatter(ceiling * level))
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.62))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                            )
                            .position(x: 30, y: min(max(12, y), geo.size.height - 8))
                    }
                }
            }
            .frame(height: height)
            .animation(Theme.quickSpring, value: history.last)
        }
    }

    private func barStack(
        values: [Double],
        gradient: LinearGradient,
        glow: Color,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(gradient)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, height * CGFloat(v / ceiling)))
                    .shadow(color: glow.opacity(0.22), radius: 3, y: 0)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}
