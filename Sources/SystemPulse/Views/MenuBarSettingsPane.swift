import SwiftUI

@MainActor
struct MenuBarSettingsPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Presentation") {
                Picker("Style", selection: $preferences.menuBarStyle) {
                    ForEach(Preferences.MenuBarStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }
            Section {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(
                        isOn: Binding(
                            get: { preferences.menuBarMetrics.contains(metric) },
                            set: { preferences.setMenuMetric(metric, enabled: $0) })
                    ) {
                        Label(metric.title, systemImage: metric.symbol)
                    }
                    .accessibilityLabel("Show \(metric.title) in menu bar")
                }
            } header: {
                Text("Metrics")
            } footer: {
                Text(
                    "At least one metric stays selected. Icon Only hides metric readings; other styles use these metrics. "
                        + "Network combines physical interfaces; Disk uses the home volume. Page selections do not change either metric."
                )
            }
            Section {
                ForEach(preferences.menuBarMetrics) { metric in
                    MenuMetricOrderRow(preferences: preferences, metric: metric)
                }
            } header: {
                Text("Display Order")
            } footer: {
                Text("Selected metrics appear from left to right in this order.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

@MainActor
private struct MenuMetricOrderRow: View {
    let preferences: Preferences
    let metric: MenuBarMetric

    var body: some View {
        LabeledContent(metric.title) {
            HStack(spacing: 8) {
                Button {
                    preferences.moveMenuMetric(metric, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(preferences.menuBarMetrics.first == metric)
                .accessibilityLabel("Move \(metric.title) earlier")
                .help("Move \(metric.title) earlier")
                Button {
                    preferences.moveMenuMetric(metric, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(preferences.menuBarMetrics.last == metric)
                .accessibilityLabel("Move \(metric.title) later")
                .help("Move \(metric.title) later")
            }
            .controlSize(.small)
        }
    }
}
