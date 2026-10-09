import SwiftUI

/// Presentation only. The parent handles optional visibility and guards navigation to hidden modules.
/// No polling, process actions, persistence, exports, or notifications originate from this card.
struct InsightsCard: View {
    let insights: [MonitoringInsight]
    let onSelect: (MetricTab) -> Void

    init(insights: [MonitoringInsight], onSelect: @escaping (MetricTab) -> Void) {
        self.insights = Array(insights.prefix(InsightEngine.maximumInsights))
        self.onSelect = onSelect
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Local insights")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if insights.isEmpty {
                    Text("No qualifying observations")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("No qualifying signal in the available readings. Missing readings are not evidence of health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(insights) { insight in
                        InsightRow(insight: insight, onSelect: onSelect)
                    }
                }

                Text("Read-only observations, evaluated on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InsightRow: View {
    let insight: MonitoringInsight
    let onSelect: (MetricTab) -> Void
    @State private var showsEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: insight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: insight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(showsEvidence ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(showsEvidence ? "Hide evidence" : "Show evidence") {
                showsEvidence.toggle()
            }
            .buttonStyle(.link)
            .font(.caption)

            Button {
                onSelect(insight.metric)
            } label: {
                Text("Show \(insight.metric.rawValue) details")
            }
            .buttonStyle(.link)
            .font(.caption)
            .help("Review \(insight.metric.rawValue) readings; no system changes are made")
        }
    }
}
