import SwiftUI

struct DashboardHeader: View {
    let store: MonitorStore
    let tab: MetricTab

    private var accent: Color { Theme.accent(for: tab.metric) }
    private var subtitle: String {
        switch tab {
        case .cpu: return "See what's working hardest."
        case .memory: return "A little room to think."
        case .network: return "Every connection, in motion."
        case .disk: return "Your space. Your activity."
        case .power: return "Follow the energy."
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("SystemPulse")
                    .font(Theme.rounded(19, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle().fill(Theme.accentGreen).frame(width: 5, height: 5)
                Text("LIVE").font(Theme.rounded(9, weight: .bold)).tracking(0.7)
            }
            .foregroundStyle(Theme.accentGreen)
            Button { store.copySnapshot() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy a snapshot of your Mac's current metrics")
            .accessibilityLabel("Copy system snapshot")
        }
    }
}
