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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(MetricTab.allCases) { tab in
                let isActive = tab == selection
                let accent = Theme.accent(for: tab.metric)

                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.rawValue)
                            .font(Theme.tabFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isActive ? accent : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accent.opacity(0.18))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.4)))

                                .matchedGeometryEffect(id: "tab-pill", in: tabNamespace, isSource: true)
                        }
                    }
                    .contentShape(Rectangle())
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
                RoundedRectangle(cornerRadius: 16).fill(Theme.insetFill)
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.insetStroke, lineWidth: 1)
            }
        )
        .animation(reduceMotion ? nil : Theme.quickSpring, value: selection)
    }

    @Namespace private var tabNamespace
}
