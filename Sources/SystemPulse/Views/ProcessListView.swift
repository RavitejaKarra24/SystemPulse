import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var focusRequest: Bool = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? Theme.accentBlue : Theme.textTertiary)
            TextField("", text: $text, prompt: Text("Search processes").foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(Theme.rowNameFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit { focused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Capsule().fill(Theme.insetFill)
                Capsule().strokeBorder(
                    focused ? Theme.accentBlue.opacity(0.45) : Theme.insetStroke,
                    lineWidth: 1
                )
            }
        )
        .onChange(of: focusRequest) { _, _ in
            focused = true
        }
        .animation(Theme.snappy, value: focused)
    }
}

/// Grouped, expandable, searchable process list (CPU / Memory tabs).
struct ProcessListCard: View {
    let store: MonitorStore
    let groups: [ProcessGroup]
    let metric: Theme.MetricType
    @Binding var searchText: String
    let onSelect: (ProcessGroup) -> Void

    @State private var expanded: Set<String> = []

    private var filtered: [ProcessGroup] {
        let sorted = groups.sorted {
            metric == .memory ? $0.totalMemory > $1.totalMemory : $0.totalCPU > $1.totalCPU
        }
        guard !searchText.isEmpty else { return Array(sorted.prefix(16)) }
        let needle = searchText.lowercased()
        return sorted.filter { group in
            group.name.lowercased().contains(needle)
                || group.processes.contains {
                    $0.name.lowercased().contains(needle)
                        || ($0.bundleIdentifier?.lowercased().contains(needle) ?? false)
                }
        }
    }

    private var maxMetricValue: Double {
        switch metric {
        case .memory:
            return Double(filtered.map(\.totalMemory).max() ?? 1)
        default:
            return max(filtered.map(\.totalCPU).max() ?? 1, 1)
        }
    }

    var body: some View {
        GlassCard(padding: 8) {
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "hourglass" : "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Text(searchText.isEmpty ? "Collecting processes…" : "No matching processes")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.dividerColor)
                                .frame(height: 1)
                                .padding(.leading, 42)
                        }
                        ProcessGroupRow(
                            store: store,
                            group: group,
                            metric: metric,
                            maxMetricValue: maxMetricValue,
                            isExpanded: expanded.contains(group.id),
                            onToggle: {
                                withAnimation(Theme.quickSpring) {
                                    if expanded.contains(group.id) {
                                        expanded.remove(group.id)
                                    } else {
                                        expanded.insert(group.id)
                                    }
                                }
                            },
                            onOpenDetail: { onSelect(group) }
                        )
                    }
                }
            }
        }
    }
}

private struct ProcessGroupRow: View {
    let store: MonitorStore
    let group: ProcessGroup
    let metric: Theme.MetricType
    let maxMetricValue: Double
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    @State private var isHovered = false

    private var accent: Color { Theme.accent(for: metric) }

    private var valueText: String {
        metric == .memory
            ? ByteFormatter.format(group.totalMemory)
            : String(format: "%.2f %%", group.totalCPU)
    }

    private var barValue: Double {
        metric == .memory ? Double(group.totalMemory) : group.totalCPU
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(group.processes.count > 1 ? 1 : 0)
                .disabled(group.processes.count <= 1)
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")

                Button(action: onOpenDetail) {
                    HStack(spacing: 8) {
                        ProcessIconView(group: group)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(group.name)
                                    .font(Theme.rowNameFont)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)

                                if group.extraCount > 0 {
                                    Text("+\(group.extraCount)")
                                        .font(Theme.badgeFont)
                                        .foregroundStyle(accent.opacity(0.95))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(accent.opacity(0.15)))
                                }
                            }

                            UsageBar(value: barValue, maxValue: maxMetricValue, color: accent, width: 72)
                        }

                        Spacer(minLength: 8)

                        Text(valueText)
                            .font(Theme.rowValueFont)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Theme.rowHover : .clear)
            )
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Show Details") { onOpenDetail() }
                Divider()
                Button("Quit") { store.quitGroup(group, force: false) }
                Button("Force Quit", role: .destructive) { store.quitGroup(group, force: true) }
                Divider()
                if !group.isSystemGroup {
                    Button("Reveal in Finder") { store.revealProcess(group) }
                }
                if let path = group.processes.first?.bundlePath ?? group.processes.first?.executablePath {
                    Button("Copy Path") { store.copyPath(path) }
                }
            }

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(group.processes.dropFirst()) { proc in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accent.opacity(0.45))
                                .frame(width: 4, height: 4)
                            Text(proc.name)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Text("pid \(proc.id)")
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                            Spacer()
                            Text(metric == .memory ? proc.memoryFormatted : proc.cpuFormatted)
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                        }
                        .padding(.leading, 38)
                        .padding(.trailing, 8)
                        .contextMenu {
                            Button("Quit") { store.quit(pid: proc.id, force: false) }
                            Button("Force Quit", role: .destructive) { store.quit(pid: proc.id, force: true) }
                            Button("Copy PID") { store.copyPath("\(proc.id)") }
                        }
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.quickSpring, value: isExpanded)
    }
}

struct ProcessIconView: View {
    let group: ProcessGroup

    var body: some View {
        Group {
            if group.isSystemGroup {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if let key = group.iconKey, let icon = ProcessMetadataProvider.icon(forKey: key) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
