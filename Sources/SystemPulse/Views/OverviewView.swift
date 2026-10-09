import SwiftUI

/// A useful landing page, not a second set of independently sampled counters.
struct OverviewView: View {
    let store: MonitorStore
    var preferences: Preferences = .shared
    let onSelect: (MetricTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your Mac, at a glance.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Live activity. A clearer picture.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                if preferences.isModuleVisible(.cpu) {
                    metricTile(
                        .cpu, value: store.hasCPUReading ? String(format: "%.0f%%", store.cpuUsage) : "—",
                        detail: !store.hasCPUReading
                            ? "Waiting for a measured interval" : "\(store.perCoreCPU.count) active cores",
                        history: store.cpuHistory, ceiling: 100)
                }
                if preferences.isModuleVisible(.memory) {
                    metricTile(
                        .memory, value: store.memoryTotal == 0 ? "—" : String(format: "%.0f%%", store.memoryUsage),
                        detail: store.memoryTotal == 0
                            ? "Waiting for samples" : "\(ByteFormatter.format(store.memoryUsed)) in use",
                        history: store.memoryHistory,
                        ceiling: Double(store.memoryTotal))
                }
                if preferences.isModuleVisible(.network) {
                    metricTile(
                        .network, value: store.netInHistory.count < 2 ? "—" : ByteFormatter.formatRate(store.netInRate),
                        detail: "↓ Download · ↑ \(ByteFormatter.formatRate(store.netOutRate))",
                        history: store.netInHistory, ceiling: nil)
                }
                if preferences.isModuleVisible(.disk) {
                    metricTile(
                        .disk, value: store.diskTotal == 0 ? "—" : ByteFormatter.format(store.diskFree),
                        detail: "Available on home volume", history: store.diskReadHistory, ceiling: nil)
                }
            }

            if preferences.isModuleVisible(.power) {
                Button {
                    onSelect(.power)
                } label: {
                    GlassCard(padding: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: store.power.hasBattery ? "battery.100percent" : "powerplug")
                                .foregroundStyle(Theme.accentGreen)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Power").font(.headline).foregroundStyle(Theme.textPrimary)
                                Text(powerDetail).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(
                                store.power.hasBattery
                                    ? (store.power.hasChargeReading
                                        ? String(format: "%.0f%%", store.power.chargePercent) : "—")
                                    : store.power.stateLabel
                            )
                            .font(Theme.valueFont).monospacedDigit().foregroundStyle(Theme.textPrimary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Power, \(store.power.stateLabel). Show power details")
            }

            if preferences.showInsights {
                InsightsCard(
                    insights: store.monitoringInsights(visibleModules: preferences.visibleModules), onSelect: onSelect)
            }

            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Current signals")
                    signalRow("Thermal state", value: thermalLabel, icon: "thermometer.medium", color: thermalColor)
                    Divider()
                    signalRow(
                        "Memory headroom",
                        value: store.memoryTotal == 0
                            ? "Sampling…" : "\(store.memoryBreakdown.pressure.rawValue) · estimate",
                        icon: "memorychip", color: Theme.pressureColor(store.memoryBreakdown.pressure))
                    if store.topProcessName != "—", preferences.isModuleVisible(.cpu) {
                        Divider()
                        Button {
                            onSelect(.cpu)
                        } label: {
                            signalRow(
                                "Top CPU consumer", value: store.topProcessName, icon: "cpu", color: Theme.textSecondary
                            )
                        }
                        .buttonStyle(.plain)
                        .help("See the apps using the most CPU")
                    }
                }
            }
            SystemFooterCard(info: store.systemInfo)
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                Text("On your Mac. Only on your Mac.")
            }
            .font(Theme.smallCaption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    private var powerDetail: String {
        if store.power.hasBattery { return store.power.timeRemainingFormatted }
        return store.power.isPluggedIn ? "No internal battery" : "Power details unavailable"
    }

    private var thermalLabel: String {
        guard store.systemInfo.uptime > 0 else { return "Sampling…" }
        switch store.systemInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Warm"
        case .serious: return "High"
        case .critical: return "Critical"
        @unknown default: return "Unavailable"
        }
    }

    private var thermalColor: Color {
        guard store.systemInfo.uptime > 0 else { return Theme.textSecondary }
        switch store.systemInfo.thermalState {
        case .nominal: return Theme.accentGreen
        case .fair: return Theme.accentOrange
        case .serious, .critical: return Theme.accentRed
        @unknown default: return Theme.textSecondary
        }
    }

    private func metricTile(_ tab: MetricTab, value: String, detail: String, history: [Double], ceiling: Double?)
        -> some View
    {
        Button {
            onSelect(tab)
        } label: {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: tab.icon).foregroundStyle(Theme.accent(for: tab.metric))
                        Text(tab.rawValue).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").foregroundStyle(Theme.textTertiary)
                    }
                    .font(Theme.captionFont)
                    Text(value)
                        .font(Theme.rounded(25, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(detail)
                        .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if tab == .disk {
                        HStack(spacing: 8) {
                            UsageBar(
                                value: Double(store.diskUsed), maxValue: Double(store.diskTotal),
                                color: Theme.accentOrange, width: 80)
                            Text(store.diskTotal == 0 ? "—" : String(format: "%.0f%% used", store.diskUsage))
                                .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                        .frame(height: 28)
                    } else {
                        MiniTrend(values: history, color: Theme.accent(for: tab.metric), ceiling: ceiling)
                            .frame(height: 28)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibleControlFocus(cornerRadius: Theme.cardCorner)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tab.rawValue), \(value), \(detail)")
        .accessibilityHint("Show \(tab.rawValue.lowercased()) details")
        .help("Show \(tab.rawValue.lowercased()) details")
    }

    private func signalRow(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16).accessibilityHidden(true)
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
        }
        .font(Theme.captionFont)
        .accessibilityElement(children: .combine)
    }
}

private struct MiniTrend: View {
    let values: [Double]
    let color: Color
    let ceiling: Double?

    var body: some View {
        Canvas { context, size in
            let samples = Array(values.suffix(30)).map { $0.isFinite ? max(0, $0) : 0 }
            guard samples.count > 1 else { return }
            let limit = max(ceiling ?? (samples.max() ?? 1) * 1.15, 1)
            let points = samples.enumerated().map { index, value in
                CGPoint(
                    x: size.width * Double(index) / Double(samples.count - 1),
                    y: size.height - 2 - (size.height - 4) * min(1, value / limit))
            }
            var line = Path()
            line.addLines(points)
            context.stroke(
                line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}
