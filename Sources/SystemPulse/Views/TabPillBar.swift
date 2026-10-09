import SwiftUI

enum MetricTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case cpu = "CPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case power = "Power"

    var id: String { rawValue }

    var metric: Theme.MetricType {
        switch self {
        case .overview, .cpu: return .cpu
        case .memory: return .memory
        case .network: return .network
        case .disk: return .disk
        case .power: return .power
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .overview: return "0"
        case .cpu: return "1"
        case .memory: return "2"
        case .network: return "3"
        case .disk: return "4"
        case .power: return "5"
        }
    }
}

/// Stable topic navigation; the selected surface stays quiet as metrics update.
struct TabPillBar: View {
    @Binding var selection: MetricTab
    var topics: [MetricTab] = MetricTab.allCases

    var body: some View {
        HStack(spacing: 3) {
            ForEach(topics) { tab in
                let isActive = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.rawValue)
                            .font(Theme.tabFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.cardFillRaised)
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardStroke))

                                .matchedGeometryEffect(id: "tab-pill", in: tabNamespace, isSource: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibleControlFocus(cornerRadius: 9)
                .help("\(tab.rawValue) (press \(tab.keyEquivalent) when not editing text)")
            }
        }
        .padding(4)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.insetFill)
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.insetStroke, lineWidth: 1)
            }
        )
        .animation(Theme.quickSpring, value: selection)
    }

    @Namespace private var tabNamespace
}
