import SwiftUI

private enum Route: Hashable {
    case process(String)
    case diskItem(String)
}

struct RootView: View {
    let store: MonitorStore
    let preferences: Preferences
    @State private var tab: MetricTab = .cpu
    @State private var path: [Route] = []
    @State private var searchFocusToken = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let route = path.last {
                    switch route {
                    case .process(let id):
                        ProcessDetailView(store: store, groupId: id, onBack: pop)
                            .id(id)
                    case .diskItem(let id):
                        DiskItemDetailView(store: store, itemId: id, onBack: pop, onDeleted: pop)
                            .id(id)
                    }
                } else {
                    MainView(
                        store: store,
                        tab: $tab,
                        searchFocusToken: $searchFocusToken,
                        onSelectProcess: { group in push(.process(group.id)) },
                        onSelectDiskItem: { item in push(.diskItem(item.id)) }
                    )
                }
            }
            .transition(Theme.pushTransition)
            .animation(Theme.smoothSpring, value: path)

            if let toast = store.toast {
                ToastBanner(toast: toast)
                    .padding(.bottom, 12)
                    .zIndex(10)
            }
        }
        .background(AppBackground())
        .fixedSize(horizontal: false, vertical: true)
        .focusable()
        .onKeyPress(.escape) {
            if !path.isEmpty {
                pop()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12345")) { press in
            guard path.isEmpty else { return .ignored }
            guard let match = MetricTab.allCases.first(where: { $0.keyEquivalent == press.characters })
            else { return .ignored }
            withAnimation(Theme.quickSpring) { tab = match }
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("f")], phases: .down) { press in
            if press.modifiers.contains(.command), path.isEmpty, (tab == .cpu || tab == .memory) {
                searchFocusToken.toggle()
                return .handled
            }
            return .ignored
        }
    }

    private func push(_ route: Route) {
        withAnimation(Theme.smoothSpring) { path.append(route) }
    }

    private func pop() {
        withAnimation(Theme.smoothSpring) { _ = path.popLast() }
    }
}

/// Top-level tab content: CPU / Memory / Network / Disk.
struct MainView: View {
    let store: MonitorStore
    @Binding var tab: MetricTab
    @Binding var searchFocusToken: Bool
    @State private var searchText: String = ""
    let onSelectProcess: (ProcessGroup) -> Void
    let onSelectDiskItem: (DiskItem) -> Void

    var body: some View {
        VStack(spacing: Theme.sectionGap) {
            TabPillBar(selection: $tab)

            OverviewStrip(store: store, tab: tab)

            switch tab {
            case .cpu:
                GraphCard(
                    history: store.cpuHistory,
                    metric: .cpu,
                    formatter: { String(format: "%.0f %%", $0) }
                )
                PerCoreCPUCard(cores: store.perCoreCPU)
                SearchField(text: $searchText, focusRequest: searchFocusToken)
                ProcessListCard(
                    store: store,
                    groups: store.processGroups,
                    metric: .cpu,
                    searchText: $searchText,
                    onSelect: onSelectProcess
                )
                SystemFooterCard(info: store.systemInfo)

            case .memory:
                GraphCard(
                    history: store.memoryHistory,
                    metric: .memory,
                    formatter: { ByteFormatter.format(UInt64(max(0, $0))) }
                )
                MemoryBreakdownCard(breakdown: store.memoryBreakdown)
                SearchField(text: $searchText, focusRequest: searchFocusToken)
                ProcessListCard(
                    store: store,
                    groups: store.processGroups,
                    metric: .memory,
                    searchText: $searchText,
                    onSelect: onSelectProcess
                )
                SystemFooterCard(info: store.systemInfo)

            case .network:
                GraphCard(
                    history: store.netInHistory,
                    metric: .network,
                    formatter: { ByteFormatter.formatRate($0) },
                    secondaryHistory: store.netOutHistory,
                    secondaryColor: Theme.accentBlue
                )
                NetworkStatsCard(store: store)
                networkLegend
                SystemFooterCard(info: store.systemInfo)

            case .disk:
                DiskGaugeCard(store: store)
                DiskIOCard(store: store)
                ScanStatusBar(store: store)
                DiskCategoryListCard(store: store, onSelectItem: onSelectDiskItem)

            case .power:
                if store.power.hasBattery {
                    BatteryGaugeCard(power: store.power)
                } else {
                    NoBatteryCard(power: store.power)
                }
                // Power is sampled every few seconds, so hold the graph back
                // until there are enough points to read as a trend.
                if store.powerDrawHistory.count >= 5 {
                    GraphCard(
                        history: store.powerDrawHistory,
                        metric: .power,
                        formatter: { String(format: "%.1f W", $0) },
                        height: 110
                    )
                }
                PowerDrawCard(power: store.power)
                if store.power.hasBattery {
                    BatteryHealthCard(power: store.power)
                }
                SystemFooterCard(info: store.systemInfo)
            }
        }
        .padding(Theme.outerPadding)
        .frame(width: Theme.popoverWidth)
        .onChange(of: tab) { _, newTab in
            if newTab != .cpu && newTab != .memory {
                searchText = ""
            }
            if newTab == .disk, !store.isScanning, !store.lastScanComplete {
                store.scanDisk()
            }
        }
    }

    private var networkLegend: some View {
        HStack(spacing: 14) {
            legendDot(color: Theme.accentTeal, label: "Download")
            legendDot(color: Theme.accentBlue, label: "Upload")
            Spacer()
            Text("Physical interfaces only")
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
