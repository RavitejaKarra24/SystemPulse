import AppKit
import SwiftUI

struct DetailHeader: View {
    let title: String
    let onBack: () -> Void

    @State private var backHovered = false

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(backHovered ? 0.12 : 0.07))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { backHovered = $0 }
            .help("Back (Esc)")
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text(title)
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Color.clear.frame(width: 30, height: 30)
        }
    }
}

/// Drill-in detail screen for a single process group — history graph, bundle
/// metadata, process hierarchy, and Quit / Force Quit actions.
struct ProcessDetailView: View {
    let store: MonitorStore
    let groupId: String
    let onBack: () -> Void

    @State private var tab: MetricTab = .cpu
    @State private var cpuHistory: [Double] = []
    @State private var memHistory: [Double] = []
    @State private var confirmForceQuit = false

    @MainActor
    private var group: ProcessGroup? {
        store.processGroups.first { $0.id == groupId }
    }

    private var activeMetric: Theme.MetricType {
        tab == .memory ? .memory : .cpu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            DetailHeader(title: group?.name ?? "Process", onBack: onBack)

            HStack(spacing: 3) {
                ForEach([MetricTab.cpu, .memory], id: \.self) { t in
                    let isActive = t == tab
                    let accent = Theme.accent(for: t.metric)
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .font(Theme.tabFont)
                            .foregroundStyle(isActive ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if isActive {
                                    Capsule()
                                        .fill(Theme.pillGradient(for: t.metric))
                                        .shadow(color: accent.opacity(0.40), radius: 8, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                ZStack {
                    Capsule().fill(Theme.insetFill)
                    Capsule().strokeBorder(Theme.insetStroke, lineWidth: 1)
                }
            )

            GraphCard(
                history: tab == .memory ? memHistory : cpuHistory,
                metric: activeMetric,
                formatter: { tab == .memory ? ByteFormatter.format(UInt64(max(0, $0))) : String(format: "%.0f %%", $0) },
                height: 120
            )
            .id(tab)

            if let group {
                HStack(spacing: 12) {
                    ProcessIconView(group: group)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(Theme.valueFont)
                            .foregroundStyle(Theme.textPrimary)
                        if let bundleId = group.processes.first?.bundleIdentifier {
                            Text(bundleId)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textTertiary)
                                .textSelection(.enabled)
                        } else if let main = group.main {
                            Text("pid \(main.id)")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                        }
                    }
                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tab == .memory ? ByteFormatter.format(group.totalMemory) : String(format: "%.2f %%", group.totalCPU))
                            .font(Theme.valueFont)
                            .foregroundStyle(Theme.accent(for: activeMetric))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("\(group.processes.count) proc · \(group.totalThreads) thr")
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                HStack(spacing: 16) {
                    if let mainPid = group.main?.id, let start = store.startDate(forPid: mainPid) {
                        LabeledInfoRow(label: "Started at", value: Self.dateFormatter.string(from: start))
                    }
                    if let mainPid = group.main?.id, let start = store.startDate(forPid: mainPid) {
                        LabeledInfoRow(
                            label: "Running for",
                            value: ByteFormatter.formatUptime(Date().timeIntervalSince(start))
                        )
                    }
                }

                if let bundlePath = group.processes.first?.bundlePath ?? group.processes.first?.executablePath {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.processes.first?.bundlePath != nil ? "Bundle path" : "Executable")
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(bundlePath)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            store.copyPath(bundlePath)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy path")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Process hierarchy", trailing: "\(group.processes.count)")

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(group.processes.enumerated()), id: \.element.id) { index, proc in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Theme.dividerColor)
                                        .frame(height: 1)
                                }
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Theme.accent(for: activeMetric).opacity(0.55))
                                        .frame(width: 5, height: 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(proc.name)
                                            .font(Theme.captionFont)
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        Text("pid \(proc.id) · \(proc.threadCount) threads")
                                            .font(Theme.smallCaption)
                                            .foregroundStyle(Theme.textTertiary)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    Text(tab == .memory ? proc.memoryFormatted : proc.cpuFormatted)
                                        .font(Theme.smallCaption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 7)
                                .contextMenu {
                                    Button("Quit") { store.quit(pid: proc.id, force: false) }
                                    Button("Force Quit", role: .destructive) { store.quit(pid: proc.id, force: true) }
                                    Button("Copy PID") { store.copyPath("\(proc.id)") }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .insetSurface(cornerRadius: 12)
                }

                HStack(spacing: 10) {
                    OutlinePillButton(title: confirmForceQuit ? "Confirm Force Quit" : "Force Quit") {
                        if confirmForceQuit {
                            store.quitGroup(group, force: true)
                            confirmForceQuit = false
                        } else {
                            confirmForceQuit = true
                        }
                    }
                    FilledPillButton(title: "Quit", color: Theme.accent(for: activeMetric)) {
                        store.quitGroup(group, force: false)
                    }
                }

                if !group.isSystemGroup {
                    Button {
                        store.revealProcess(group)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text("Reveal in Finder")
                        }
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Process has exited.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .padding(Theme.outerPadding)
        .frame(width: Theme.popoverWidth)
        .onChange(of: group?.totalCPU) { _, _ in recordSample() }
        .onChange(of: group?.totalMemory) { _, _ in recordSample() }
        .onAppear { recordSample() }
        .onChange(of: groupId) { _, _ in
            cpuHistory = []
            memHistory = []
            confirmForceQuit = false
            recordSample()
        }
    }

    @MainActor
    private func recordSample() {
        guard let group else { return }
        cpuHistory.append(group.totalCPU)
        memHistory.append(Double(group.totalMemory))
        if cpuHistory.count > MonitorStore.historyLimit { cpuHistory.removeFirst() }
        if memHistory.count > MonitorStore.historyLimit { memHistory.removeFirst() }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}

struct LabeledInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }
}
