import SwiftUI

private enum Route: Hashable {
    case process(String)
    case diskItem(String)
}

struct RootView: View {
    let store: MonitorStore
    let preferences: Preferences
    var panelHeight: CGFloat = 720
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: MetricTab = .cpu
    @State private var path: [Route] = []
    @State private var searchFocusToken = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let route = path.last {
                    switch route {
                    case .process(let id):
                        ScrollView {
                            ProcessDetailView(store: store, groupId: id, onBack: pop)
                        }.id(id)
                    case .diskItem(let id):
                        ScrollView {
                            DiskItemDetailView(store: store, itemId: id, onBack: pop, onDeleted: pop)
                        }.id(id)
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
            .transition(.opacity)
            .animation(reduceMotion ? nil : Theme.pageAnimation, value: path)

            if let toast = store.toast {
                ToastBanner(toast: toast)
                    .padding(.bottom, 12)
                    .zIndex(10)
            }
        }
        .background(AppBackground())
        .frame(width: Theme.popoverWidth, height: panelHeight, alignment: .top)
        .clipped()
        .preferredColorScheme(.dark)
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
            tab = match
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
        path.append(route)
    }

    private func pop() {
        _ = path.popLast()
    }
}

/// Stable panel chrome with an independently transitioning, scrollable topic page.
struct MainView: View {
    let store: MonitorStore
    @Binding var tab: MetricTab
    @Binding var searchFocusToken: Bool
    @State private var searchText: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelectProcess: (ProcessGroup) -> Void
    let onSelectDiskItem: (DiskItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(store: store, tab: tab)
                .padding(.horizontal, Theme.outerPadding)
                .padding(.top, 16)
                .padding(.bottom, 14)
            TabPillBar(selection: $tab)
                .padding(.horizontal, Theme.outerPadding)
                .padding(.bottom, 12)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: Theme.sectionGap) {
                        OverviewStrip(store: store, tab: tab)
                        topicContent
                    }
                    .padding(.horizontal, Theme.outerPadding)
                    .padding(.bottom, Theme.outerPadding)
                    // Only the page fades; its graphs and rows never inherit
                    // the navigation animation or interpolate unrelated data.
                    .transaction { $0.animation = nil }
                }
                .id(tab)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : Theme.pageAnimation, value: tab)
            .clipped()
        }
        .frame(width: Theme.popoverWidth)
        .onChange(of: tab) { _, newTab in
            if newTab != .cpu && newTab != .memory { searchText = "" }
            if newTab == .disk, !store.isScanning, !store.lastScanComplete {
                store.scanDisk()
            }
        }
    }

    @ViewBuilder private var topicContent: some View {
        switch tab {
        case .cpu:
            GraphCard(
                history: store.cpuHistory,
                metric: .cpu,
                formatter: { String(format: "%.0f%%", $0) },
                fixedCeiling: 100,
                title: "CPU activity"
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
                formatter: { ByteFormatter.format(UInt64(max(0, $0))) },
                fixedCeiling: Double(store.memoryTotal),
                title: "Memory footprint"
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
                secondaryColor: Theme.accentBlue,
                title: "Network traffic",
                primaryLabel: "Download", secondaryLabel: "Upload"
            )
            NetworkStatsCard(store: store)
            SystemFooterCard(info: store.systemInfo)

        case .disk:
            DiskGaugeCard(store: store)
            ScanStatusBar(store: store)
            GraphCard(
                history: store.diskReadHistory, metric: .disk,
                formatter: { ByteFormatter.formatRate($0) }, height: 100,
                secondaryHistory: store.diskWriteHistory, secondaryColor: Theme.accentViolet,
                title: "Disk activity", primaryLabel: "Read", secondaryLabel: "Write"
            )
            DiskIOCard(store: store)
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
                    height: 110,
                    title: "Power draw"
                )
            }
            PowerDrawCard(power: store.power)
            if store.power.hasBattery {
                BatteryHealthCard(power: store.power)
            }
            SystemFooterCard(info: store.systemInfo)
        }
    }
}
