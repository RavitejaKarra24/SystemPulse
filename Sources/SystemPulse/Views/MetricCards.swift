import SwiftUI

// MARK: - Overview strip (live headline stats)

struct OverviewStrip: View {
    let store: MonitorStore
    let tab: MetricTab

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 0) {
                switch tab {
                case .cpu:
                    metricBlock(
                        title: "CPU",
                        value: String(format: "%.0f%%", store.cpuUsage),
                        subtitle: "peak \(String(format: "%.0f%%", store.cpuPeak))",
                        color: Theme.loadColor(store.cpuUsage)
                    )
                    divider
                    metricBlock(
                        title: "Load",
                        value: String(format: "%.2f", store.systemInfo.loadAverage1),
                        subtitle: String(format: "%.2f · %.2f", store.systemInfo.loadAverage5, store.systemInfo.loadAverage15),
                        color: Theme.accentBlue
                    )
                    divider
                    metricBlock(
                        title: "Top",
                        value: truncated(store.topProcessName, 10),
                        subtitle: String(format: "%.1f%%", store.topProcessCPU),
                        color: Theme.accent(for: .cpu)
                    )
                case .memory:
                    metricBlock(
                        title: "Used",
                        value: String(format: "%.0f%%", store.memoryUsage),
                        subtitle: ByteFormatter.format(store.memoryUsed),
                        color: Theme.loadColor(store.memoryUsage)
                    )
                    divider
                    metricBlock(
                        title: "Pressure",
                        value: store.memoryBreakdown.pressure.rawValue,
                        subtitle: "of \(ByteFormatter.format(store.memoryTotal))",
                        color: Theme.pressureColor(store.memoryBreakdown.pressure)
                    )
                    divider
                    metricBlock(
                        title: "Wired",
                        value: ByteFormatter.format(store.memoryBreakdown.wired),
                        subtitle: "compressed \(ByteFormatter.format(store.memoryBreakdown.compressed))",
                        color: Theme.accentViolet
                    )
                case .network:
                    metricBlock(
                        title: "Down",
                        value: ByteFormatter.formatRate(store.netInRate),
                        subtitle: "peak \(ByteFormatter.formatRate(store.netInPeak))",
                        color: Theme.accentBlue
                    )
                    divider
                    metricBlock(
                        title: "Up",
                        value: ByteFormatter.formatRate(store.netOutRate),
                        subtitle: "peak \(ByteFormatter.formatRate(store.netOutPeak))",
                        color: Theme.accentTeal
                    )
                    divider
                    metricBlock(
                        title: "Session",
                        value: ByteFormatter.format(store.sessionBytesIn + store.sessionBytesOut),
                        subtitle: "total transferred",
                        color: Theme.accent(for: .network)
                    )
                case .disk:
                    metricBlock(
                        title: "Used",
                        value: String(format: "%.0f%%", store.diskUsage),
                        subtitle: ByteFormatter.format(store.diskUsed),
                        color: Theme.loadColor(store.diskUsage)
                    )
                    divider
                    metricBlock(
                        title: "Free",
                        value: ByteFormatter.format(store.diskFree),
                        subtitle: "of \(ByteFormatter.format(store.diskTotal))",
                        color: Theme.accentGreen
                    )
                    divider
                    metricBlock(
                        title: "Found",
                        value: store.reclaimableBytes > 0 ? ByteFormatter.format(store.reclaimableBytes) : "—",
                        subtitle: store.isScanning ? "scanning…" : "reclaimable",
                        color: Theme.accentOrange
                    )
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.dividerColor)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 8)
    }

    private func metricBlock(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Theme.smallCaption)
                .tracking(0.5)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.valueFont)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func truncated(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }
}

// MARK: - Per-core CPU

struct PerCoreCPUCard: View {
    let cores: [Double]

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Per-Core", trailing: "\(cores.count) cores")

                if cores.isEmpty {
                    Text("Sampling…")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(cores.count, 8))
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { index, usage in
                            VStack(spacing: 4) {
                                GeometryReader { geo in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Theme.trackColor)
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Theme.barGradient(for: .cpu))
                                            .frame(height: max(3, geo.size.height * CGFloat(usage / 100)))
                                            .shadow(color: Theme.accentBlue.opacity(0.25), radius: 2, y: 0)
                                    }
                                }
                                .frame(height: 36)

                                Text("\(index)")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Memory breakdown

struct MemoryBreakdownCard: View {
    let breakdown: MemoryBreakdown

    private struct Segment: Identifiable {
        let id: String
        let label: String
        let bytes: UInt64
        let color: Color
    }

    private var segments: [Segment] {
        [
            .init(id: "app", label: "App", bytes: breakdown.app, color: Theme.accentBlue),
            .init(id: "wired", label: "Wired", bytes: breakdown.wired, color: Theme.accentViolet),
            .init(id: "compressed", label: "Compressed", bytes: breakdown.compressed, color: Theme.accentTeal),
            .init(id: "cached", label: "Cached", bytes: breakdown.cached, color: Theme.accentOrange),
            .init(id: "free", label: "Free", bytes: breakdown.free, color: Theme.accentGreen.opacity(0.7)),
        ]
    }

    private var total: Double {
        Double(max(breakdown.total, 1))
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Breakdown")
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.pressureColor(breakdown.pressure))
                            .frame(width: 6, height: 6)
                        Text(breakdown.pressure.rawValue + " pressure")
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.pressureColor(breakdown.pressure))
                    }
                }

                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(segments) { seg in
                            let w = max(seg.bytes > 0 ? 4 : 0, geo.size.width * CGFloat(Double(seg.bytes) / total) - 2)
                            if seg.bytes > 0 {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(seg.color)
                                    .frame(width: w)
                                    .help("\(seg.label): \(ByteFormatter.format(seg.bytes))")
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Legend
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(segments) { seg in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(seg.color)
                                .frame(width: 8, height: 8)
                            Text(seg.label)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 0)
                            Text(ByteFormatter.format(seg.bytes))
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Network stats

struct NetworkStatsCard: View {
    let store: MonitorStore

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                rateRow(
                    icon: "arrow.down.circle.fill",
                    label: "Download",
                    rate: store.netInRate,
                    peak: store.netInPeak,
                    total: store.sessionBytesIn,
                    color: Theme.accentBlue
                )
                Rectangle()
                    .fill(Theme.dividerColor)
                    .frame(height: 1)
                rateRow(
                    icon: "arrow.up.circle.fill",
                    label: "Upload",
                    rate: store.netOutRate,
                    peak: store.netOutPeak,
                    total: store.sessionBytesOut,
                    color: Theme.accentTeal
                )
            }
        }
    }

    private func rateRow(
        icon: String,
        label: String,
        rate: Double,
        peak: Double,
        total: UInt64,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.rowNameFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("peak \(ByteFormatter.formatRate(peak)) · session \(ByteFormatter.format(total))")
                    .font(Theme.smallCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            Spacer()
            Text(ByteFormatter.formatRate(rate))
                .font(Theme.rowValueFont)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

// MARK: - System footer

struct SystemFooterCard: View {
    let info: SystemInfo

    var body: some View {
        HStack(spacing: 10) {
            footerItem(icon: "clock", text: ByteFormatter.formatUptime(info.uptime))
            bullet
            footerItem(icon: "square.stack.3d.up", text: "\(info.processCount) procs")
            bullet
            footerItem(icon: thermalIcon, text: thermalLabel)
        }
        .font(Theme.smallCaption)
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var bullet: some View {
        Text("·").opacity(0.5)
    }

    private func footerItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
        }
    }

    private var thermalIcon: String {
        switch info.thermalState {
        case .nominal: return "thermometer.medium"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "thermometer.high"
        @unknown default: return "thermometer.medium"
        }
    }

    private var thermalLabel: String {
        switch info.thermalState {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Thermal"
        }
    }
}
