import SwiftUI

// MARK: - Battery gauge

/// Headline battery readout: a horizontal cell with charge level, state, and
/// the time estimate macOS itself publishes.
struct BatteryGaugeCard: View {
    let power: PowerInfo

    private var accent: Color {
        if power.isCharging || power.isPluggedIn { return Theme.accentGreen }
        if power.chargePercent <= 10 { return Theme.accentRed }
        if power.chargePercent <= 20 { return Theme.accentOrange }
        return Theme.accentGreen
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f%%", power.chargePercent))
                        .font(Theme.bigValueFont)
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    if power.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accentYellow)
                            .accessibilityHidden(true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(power.stateLabel)
                            .font(Theme.rowValueFont)
                            .foregroundStyle(Theme.textPrimary)
                        Text(power.timeRemainingFormatted)
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                batteryCell
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(format: "Battery %.0f percent, %@, %@",
                   power.chargePercent, power.stateLabel, power.timeRemainingFormatted)
        )
    }

    /// Battery outline with a nub on the right, filled to the current level.
    private var batteryCell: some View {
        HStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.trackColor)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.75), accent],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(power.chargePercent / 100)))
                        .shadow(color: accent.opacity(0.35), radius: 5)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
            }
            .frame(height: 22)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.white.opacity(0.20))
                .frame(width: 3, height: 9)
        }
        .animation(Theme.smoothSpring, value: power.chargePercent)
    }
}

// MARK: - Battery health

struct BatteryHealthCard: View {
    let power: PowerInfo

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Battery Health")
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(power.isHealthy ? Theme.accentGreen : Theme.accentOrange)
                            .frame(width: 6, height: 6)
                        Text(power.condition)
                            .font(Theme.smallCaption)
                            .foregroundStyle(power.isHealthy ? Theme.accentGreen : Theme.accentOrange)
                    }
                }

                if power.healthPercent > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.trackColor)
                                Capsule()
                                    .fill(power.isHealthy ? Theme.accentGreen : Theme.accentOrange)
                                    .frame(width: max(4, geo.size.width * CGFloat(power.healthPercent / 100)))
                            }
                        }
                        .frame(height: 6)

                        Text(String(format: "%.0f%% of design capacity", power.healthPercent))
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    detailRow("Cycles", cycleText)
                    detailRow("Capacity", capacityText)
                    if let temp = power.temperatureC {
                        detailRow("Temperature", String(format: "%.1f °C", temp))
                    }
                    if let flow = power.batteryPowerWatts, abs(flow) >= 0.05 {
                        detailRow(flow > 0 ? "Charging at" : "Discharging at",
                                  String(format: "%.1f W", abs(flow)))
                    }
                }
            }
        }
    }

    private var cycleText: String {
        guard power.designCycleCount > 0 else { return "\(power.cycleCount)" }
        return "\(power.cycleCount) of \(power.designCycleCount)"
    }

    private var capacityText: String {
        guard power.fullChargeCapacity > 0, power.designCapacity > 0 else { return "—" }
        return "\(power.fullChargeCapacity) / \(power.designCapacity) mAh"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - Adapter and draw

struct PowerDrawCard: View {
    let power: PowerInfo

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                row(
                    icon: "bolt.circle.fill",
                    label: "System Draw",
                    detail: "measured at the wall",
                    value: power.systemPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                    color: Theme.accentYellow
                )
                Rectangle()
                    .fill(Theme.dividerColor)
                    .frame(height: 1)
                row(
                    icon: power.isPluggedIn ? "powerplug.fill" : "powerplug",
                    label: adapterLabel,
                    detail: power.isPluggedIn ? "connected" : "not connected",
                    value: power.adapterWatts.map { "\($0) W" } ?? "—",
                    color: power.isPluggedIn ? Theme.accentGreen : Theme.textTertiary
                )
            }
        }
    }

    private var adapterLabel: String {
        guard let name = power.adapterName, !name.isEmpty else { return "Power Adapter" }
        return name.trimmingCharacters(in: .whitespaces)
    }

    private func row(
        icon: String,
        label: String,
        detail: String,
        value: String,
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
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.smallCaption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.rowValueFont)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Desktop / no-battery state

struct NoBatteryCard: View {
    let power: PowerInfo

    var body: some View {
        GlassCard(padding: 20) {
            VStack(spacing: 10) {
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accentGreen)
                Text("Running on AC power")
                    .font(Theme.rowNameFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("No internal battery detected on this Mac.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
