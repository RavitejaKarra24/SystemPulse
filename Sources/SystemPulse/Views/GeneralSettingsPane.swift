import SwiftUI

@MainActor
struct GeneralSettingsPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { preferences.setLaunchAtLogin($0) }))
                Text(preferences.loginStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = preferences.loginError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Appearance and Updates") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(Preferences.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Picker("Refresh rate", selection: $preferences.refreshRate) {
                    ForEach(Preferences.RefreshRate.allCases) { rate in
                        Text(rate.label).tag(rate)
                    }
                }
                Text("Slower updates reduce background work. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show insights on Overview", isOn: $preferences.showInsights)
            }
            Section {
                ForEach(MetricTab.allCases.filter { $0 != .overview }) { tab in
                    Toggle(
                        tab.rawValue,
                        isOn: Binding(
                            get: { preferences.isModuleVisible(tab) },
                            set: { preferences.setModule(tab, enabled: $0) })
                    )
                }
            } header: {
                Text("Visible Modules")
            } footer: {
                Text(
                    "Overview is always available. At least one module stays visible; CPU is restored if all are hidden."
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear { preferences.refreshLaunchAtLoginStatus() }
    }
}
