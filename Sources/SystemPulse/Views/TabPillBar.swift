import SwiftUI

enum MetricTab: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case power = "Power"

    var id: String { rawValue }

    var metric: Theme.MetricType {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .network: return .network
        case .disk: return .disk
        case .power: return .power
        }
    }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .cpu: return "1"
        case .memory: return "2"
        case .network: return "3"
        case .disk: return "4"
        case .power: return "5"
        }
    }
}

/// The rounded segmented control at the top of the panel (CPU / Memory / Network / Disk).
struct TabPillBar: View {
    @Binding var selection: MetricTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(MetricTab.allCases) { tab in
                let isActive = tab == selection
                let accent = Theme.accent(for: tab.metric)

                Button {
                    withAnimation(Theme.quickSpring) { selection = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(tab.rawValue)
                            .font(Theme.tabFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isActive ? .white : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isActive {
                            Capsule()
                                .fill(Theme.pillGradient(for: tab.metric))
                                .shadow(color: accent.opacity(0.40), radius: 8, y: 1)
                                .matchedGeometryEffect(id: "tab-pill", in: tabNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(tab.rawValue) (press \(tab.keyEquivalent))")
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(
            ZStack {
                Capsule().fill(Theme.insetFill)
                Capsule().strokeBorder(Theme.insetStroke, lineWidth: 1)
            }
        )
    }

    @Namespace private var tabNamespace
}
