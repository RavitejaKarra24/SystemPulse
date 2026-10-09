import SwiftUI

struct DashboardHeader: View {
    let store: MonitorStore
    let tab: MetricTab
    var preferences: Preferences = .shared
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.insetFill, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("SystemPulse")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(tab == .overview ? "Personal system monitor" : "\(tab.rawValue) insights")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().fill(Theme.accentGreen).frame(width: 5, height: 5).accessibilityHidden(true)
                Text(store.cpuHistory.isEmpty ? "Starting" : "Live")
                    .font(Theme.smallCaption)
            }
            .foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .combine)
            DiagnosticsExportButton(makeSnapshot: { store.diagnosticSnapshot() }) { message, isError in
                store.showToast(message, isError: isError)
            }
            .frame(width: 26, height: 28)
            Button {
                store.copySnapshot()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.insetFill, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibleControlFocus()
            .help("Copy system snapshot (⌘⇧C)")
            .accessibilityLabel("Copy system snapshot")
            Button {
                if let onOpenSettings {
                    onOpenSettings()
                } else {
                    SettingsWindowController.show(preferences: preferences)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.insetFill, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .accessibleControlFocus()
            .help("Settings (⌘,)")
            .accessibilityLabel("Open SystemPulse settings")
        }
    }
}
