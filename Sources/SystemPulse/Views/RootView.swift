import SwiftUI

private enum Route: Hashable {
    case process(String)
    case diskItem(String)
}

struct RootView: View {
    let store: MonitorStore
    let preferences: Preferences
    var panelHeight: CGFloat = 720
    var onOpenSettings: (() -> Void)? = nil
    @State private var tab: MetricTab = .overview
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
                        preferences: preferences,
                        tab: $tab,
                        searchFocusToken: $searchFocusToken,
                        onSelectProcess: { group in push(.process(group.id)) },
                        onSelectDiskItem: { item in push(.diskItem(item.id)) },
                        onOpenSettings: onOpenSettings
                    )
                }
            }
            .transition(.opacity)
            .animation(Theme.pageAnimation, value: path)

            if let toast = store.toast {
                ToastBanner(toast: toast, onDismiss: { store.dismissToast(id: toast.id) })
                    .padding(.bottom, 12)
                    .zIndex(10)
            }
        }
        .background(AppBackground())
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onChange(of: preferences.visibleModules) {
            if !preferences.isModuleVisible(tab) {
                tab = .overview
                path.removeAll()
            }
        }
        .onChange(of: preferences.refreshRate) { store.synchronizePollingPreferences() }
        .frame(width: Theme.popoverWidth, height: panelHeight, alignment: .top)
        .clipped()

        .focusable()
        .onKeyPress(keys: [.escape], phases: .down) { press in
            guard
                PanelKeyboardPolicy.allowsNamedKey(
                    modifiers: press.modifiers, isEditingText: PanelKeyboardPolicy.textResponderIsActive
                )
            else { return .ignored }
            if !path.isEmpty {
                pop()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "012345")) { press in
            guard
                let match = PanelKeyboardPolicy.topic(
                    characters: press.characters, modifiers: press.modifiers,
                    isEditingText: PanelKeyboardPolicy.textResponderIsActive,
                    hasDetail: !path.isEmpty, topics: preferences.displayedTopics
                )
            else { return .ignored }
            tab = match
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("f")], phases: .down) { press in
            if PanelKeyboardPolicy.allowsProcessSearch(
                modifiers: press.modifiers, hasDetail: !path.isEmpty, topic: tab)
            {
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
    var preferences: Preferences = .shared
    @Binding var tab: MetricTab
    @Binding var searchFocusToken: Bool
    @State private var searchText: String = ""
    let onSelectProcess: (ProcessGroup) -> Void
    let onSelectDiskItem: (DiskItem) -> Void
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(store: store, tab: tab, preferences: preferences, onOpenSettings: onOpenSettings)
                .padding(.horizontal, Theme.outerPadding)
                .padding(.top, 16)
                .padding(.bottom, 14)
            TabPillBar(selection: $tab, topics: preferences.displayedTopics)
                .padding(.horizontal, Theme.outerPadding)
                .padding(.bottom, 12)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: Theme.sectionGap) {
                        if tab != .overview && tab != .disk {
                            OverviewStrip(store: store, tab: tab)
                        }
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
            .animation(Theme.pageAnimation, value: tab)
            .clipped()
        }
        .frame(width: Theme.popoverWidth)
        .onChange(of: preferences.visibleModules) {
            if !preferences.isModuleVisible(tab) { tab = .overview }
        }
        .onChange(of: tab) { _, newTab in
            if newTab != .cpu && newTab != .memory { searchText = "" }
        }
    }

    @ViewBuilder private var topicContent: some View {
        switch tab {
        case .overview:
            OverviewView(
                store: store, preferences: preferences,
                onSelect: { target in
                    if preferences.isModuleVisible(target) { tab = target }
                })
        case .cpu:
            GraphCard(
                history: store.cpuHistory,
                metric: .cpu,
                formatter: { String(format: "%.0f%%", $0) },
                fixedCeiling: 100,
                title: "CPU activity",
                timedHistory: store.cpuTimeline
            )
            PerCoreCPUCard(cores: store.hasCPUReading ? store.perCoreCPU : [])
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
                title: "Memory footprint",
                timedHistory: store.memoryTimeline
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
            NetworkInterfacePicker(
                interfaces: store.networkInterfaces,
                selection: Binding(
                    get: { store.selectedNetworkInterfaceID }, set: { store.selectedNetworkInterfaceID = $0 })
            )
            if store.selectedNetworkInterfaceID != nil {
                Text(
                    "Interface chart starts when selected. Totals are since monitoring began; a disconnected interface leaves a gap."
                )
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            GraphCard(
                history: store.netInHistory,
                metric: .network,
                formatter: { ByteFormatter.formatRate($0) },
                secondaryHistory: store.netOutHistory,
                secondaryColor: Theme.accentBlue,
                title: store.selectedNetworkInterfaceID == nil ? "All-interface traffic" : "Interface traffic",
                primaryLabel: "Download", secondaryLabel: "Upload",
                timedHistory: store.networkPageDownloadTimeline,
                secondaryTimedHistory: store.networkPageUploadTimeline
            )
            .id(store.selectedNetworkInterfaceID ?? "aggregate")
            NetworkStatsCard(store: store)
            NetworkInterfacesCard(
                interfaces: store.networkInterfaces,
                selection: Binding(
                    get: { store.selectedNetworkInterfaceID }, set: { store.selectedNetworkInterfaceID = $0 }),
                showsPicker: false
            )
            SystemFooterCard(info: store.systemInfo)

        case .disk:
            VolumePickerCard(
                volumes: store.volumes,
                selection: Binding(get: { store.selectedVolumeID }, set: { store.selectedVolumeID = $0 })
            )
            DiskGaugeCard(store: store, volume: store.selectedVolume)
            GraphCard(
                history: store.diskReadHistory, metric: .disk,
                formatter: { ByteFormatter.formatRate($0) }, height: 100,
                secondaryHistory: store.diskWriteHistory, secondaryColor: Theme.accentViolet,
                title: "All-device disk activity", primaryLabel: "Read", secondaryLabel: "Write",
                timedHistory: store.diskReadTimeline,
                secondaryTimedHistory: store.diskWriteTimeline
            )
            DiskIOCard(store: store)
            SectionLabel(text: store.scanScope.isReadOnly ? "Folder inventory" : "Home-folder cleanup")
            ScanStatusBar(store: store)
            CleanupQueueCard(store: store)
            if store.scanScope.isReadOnly {
                FolderInventoryCard(store: store)
                    .id(store.diskScanRevision)
            } else {
                DiskCategoryListCard(store: store, onSelectItem: onSelectDiskItem)
            }

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
                    title: "Power draw",
                    timedHistory: store.powerDrawTimeline
                )
            }
            PowerDiagnosticsCard(power: store.power)
            PowerDrawCard(power: store.power)
            if store.power.hasBattery {
                BatteryHealthCard(power: store.power)
            }
            SystemFooterCard(info: store.systemInfo)
        }
    }
}
