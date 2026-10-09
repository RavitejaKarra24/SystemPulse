import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var focusRequest: Bool = false

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? Theme.accentBlue : Theme.textTertiary)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text("Search processes").foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(Theme.rowNameFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .accessibilityLabel("Search processes")
                .accessibilityHint("Search by name, PID, executable path, or bundle identifier.")
                .onSubmit { focused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibleControlFocus(cornerRadius: 11)
                .accessibilityLabel("Clear process search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Capsule().fill(Theme.insetFill)
                Capsule().strokeBorder(
                    focused
                        ? Color(nsColor: .keyboardFocusIndicatorColor)
                        : (contrast == .increased ? Theme.textSecondary : Theme.insetStroke),
                    lineWidth: focused ? 2 : 1
                )
            }
        )
        .onChange(of: focusRequest) { _, _ in
            focused = true
        }
        .animation(reduceMotion ? nil : Theme.snappy, value: focused)
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
    @State private var showAll = false
    @State private var forceQuitTarget: ProcessActionTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let previewLimit = 16

    var body: some View {
        // Search never truncates matching groups; browsing makes the limit explicit.
        let query = ProcessQuery(searchText)
        let matchingGroups = query.apply(to: groups, sortBy: metric == .memory ? .memory : .cpu)
        let visibleGroups =
            query.isSearching || showAll
            ? matchingGroups : Array(matchingGroups.prefix(Self.previewLimit))
        let maxMetricValue = max(
            visibleGroups.map {
                metric == .memory ? Double($0.totalMemory) : $0.totalCPU
            }.max() ?? 1, 1)
        GlassCard(padding: 8) {
            VStack(spacing: 8) {
                HStack {
                    Text(
                        query.isSearching
                            ? "Search results"
                            : (showAll || matchingGroups.count <= 16 ? "All groups" : "Top 16 groups")
                    )
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(visibleGroups.count) of \(groups.count) groups")
                        .font(Theme.smallCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 6)
                .accessibilityElement(children: .combine)

                if visibleGroups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: query.isSearching ? "magnifyingglass" : "hourglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Text(query.isSearching ? "No matching processes" : "Collecting processes…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                            VStack(spacing: 0) {
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
                                        withAnimation(reduceMotion ? nil : Theme.quickSpring) {
                                            if expanded.contains(group.id) {
                                                expanded.remove(group.id)
                                            } else {
                                                expanded.insert(group.id)
                                            }
                                        }
                                    },
                                    onOpenDetail: { onSelect(group) },
                                    onForceQuit: { forceQuitTarget = $0 }
                                )
                            }
                        }
                    }
                }

                if !query.isSearching && (groups.count > Self.previewLimit || showAll) {
                    Button(showAll ? "Show fewer" : "Show all \(groups.count) groups") {
                        showAll.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.accentBlue)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .accessibleControlFocus()
                    .accessibilityHint(showAll ? "Show only the top 16 groups." : "Show every process group.")
                }
            }
        }
        .processForceQuitConfirmation(store: store, target: $forceQuitTarget)
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
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
    let onForceQuit: (ProcessActionTarget) -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibleControlFocus(cornerRadius: 4)
                .opacity(group.processes.count > 1 ? 1 : 0)
                .disabled(group.processes.count <= 1)
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(group.name) processes")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHidden(group.processes.count <= 1)

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
                                .accessibilityHidden(true)
                        }

                        Spacer(minLength: 8)

                        Text(valueText)
                            .font(Theme.rowValueFont)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibleControlFocus(cornerRadius: 6)
                .accessibilityLabel(
                    "\(group.name), \(group.processes.count) processes, \(metric == .memory ? "memory" : "CPU") \(valueText)"
                )
                .accessibilityHint("Show process details.")
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
                let target = ProcessActionTarget.group(group)
                Button("Quit") { target.quit(using: store, force: false) }
                    .disabled(!target.isAllowed)
                Button("Force Quit…", role: .destructive) { onForceQuit(target) }
                    .disabled(!target.isAllowed)
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
                                .accessibilityHidden(true)
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
                            let target = ProcessActionTarget.process(proc, in: group)
                            Button("Quit") { target.quit(using: store, force: false) }
                                .disabled(!target.isAllowed)
                            Button("Force Quit…", role: .destructive) { onForceQuit(target) }
                                .disabled(!target.isAllowed)
                            Button("Copy PID") { store.copyPath("\(proc.id)") }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.bottom, 8)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : Theme.quickSpring, value: isExpanded)
    }
}

struct ProcessIconView: View {
    let group: ProcessGroup

    var body: some View {
        Group {
            if group.isSystemGroup {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.insetFill)
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
                    .fill(Theme.insetFill)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// All process termination entry points share the same UI safety rules.
/// Resolve the current group again when an alert is confirmed, not its old snapshot.
enum ProcessActionTarget {
    case group(ProcessGroup)
    case process(ProcessStat, in: ProcessGroup)

    var isAllowed: Bool {
        switch self {
        case .group(let group):
            return !group.isSystemGroup && !group.processes.isEmpty
                && group.processes.allSatisfy { $0.id > 1 && $0.id != ProcessInfo.processInfo.processIdentifier }
        case .process(let process, in: let group):
            return !group.isSystemGroup && process.id > 1
                && process.id != ProcessInfo.processInfo.processIdentifier
        }
    }

    var message: String {
        switch self {
        case .group(let group):
            return "Force quit \(group.name) (\(group.processes.count) processes)? Unsaved changes may be lost."
        case .process(let process, in: _):
            return "Force quit \(process.name) (PID \(process.id))? Unsaved changes may be lost."
        }
    }

    @MainActor
    func quit(using store: MonitorStore, force: Bool) {
        guard isAllowed else { return }
        switch self {
        case .group(let original):
            guard let current = store.processGroups.first(where: { $0.id == original.id }),
                Self.group(current).isAllowed
            else { return }
            store.quitGroup(current, force: force)
        case .process(let original, in: let originalGroup):
            guard let currentGroup = store.processGroups.first(where: { $0.id == originalGroup.id }),
                let current = currentGroup.processes.first(where: { $0.id == original.id }),
                Self.process(current, in: currentGroup).isAllowed
            else { return }
            store.quit(pid: current.id, force: force)
        }
    }
}

private struct ProcessForceQuitConfirmation: ViewModifier {
    let store: MonitorStore
    @Binding var target: ProcessActionTarget?

    func body(content: Content) -> some View {
        content.alert(
            "Force Quit?",
            isPresented: Binding(
                get: { target != nil },
                set: { if !$0 { target = nil } }
            ), presenting: target
        ) { pending in
            Button("Force Quit", role: .destructive) {
                pending.quit(using: store, force: true)
                target = nil
            }
            .disabled(!pending.isAllowed)
            .keyboardShortcut(DestructiveConfirmationKeyboard.destructiveShortcut)
            Button("Cancel", role: .cancel) { target = nil }
                .keyboardShortcut(DestructiveConfirmationKeyboard.cancelShortcut)
        } message: { pending in
            Text(pending.message)
        }
    }
}

extension View {
    func processForceQuitConfirmation(store: MonitorStore, target: Binding<ProcessActionTarget?>) -> some View {
        modifier(ProcessForceQuitConfirmation(store: store, target: target))
    }
}
