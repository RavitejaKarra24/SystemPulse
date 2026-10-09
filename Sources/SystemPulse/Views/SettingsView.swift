import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, menuBar, alerts

    var id: Self { self }
    var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .alerts: return "Alerts"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .alerts: return "bell"
        }
    }
}

@MainActor
struct SettingsView: View {
    let preferences: Preferences
    let notifications: LocalNotificationService
    @State private var selectedPane: SettingsPane?

    init(
        preferences: Preferences,
        notifications: LocalNotificationService,
        initialPane: SettingsPane = .general
    ) {
        self.preferences = preferences
        self.notifications = notifications
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
            .accessibilityLabel("Settings categories")
        } detail: {
            SettingsDetailView(
                pane: selectedPane ?? .general,
                preferences: preferences,
                notifications: notifications)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(preferences.appearance.colorScheme)
    }
}

@MainActor
private struct SettingsDetailView: View {
    let pane: SettingsPane
    let preferences: Preferences
    let notifications: LocalNotificationService

    var body: some View {
        Group {
            switch pane {
            case .general:
                GeneralSettingsPane(preferences: preferences)
            case .menuBar:
                MenuBarSettingsPane(preferences: preferences)
            case .alerts:
                AlertsSettingsPane(preferences: preferences, notifications: notifications)
            }
        }
        .navigationTitle(pane.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
