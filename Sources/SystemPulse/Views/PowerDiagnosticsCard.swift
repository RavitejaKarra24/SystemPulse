import SwiftUI

struct PowerDiagnosticsCard: View {
    let power: PowerInfo
    @State private var sourcesExpanded = false

    private var modeLabel: String {
        power.lowPowerModeEnabled.map { $0 ? "Enabled" : "Disabled" } ?? "Unavailable"
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Energy settings")
                HStack(spacing: 8) {
                    Image(systemName: "leaf")
                        .foregroundStyle(power.lowPowerModeEnabled == true ? Theme.accentGreen : Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text("Low Power Mode").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(modeLabel).foregroundStyle(Theme.textSecondary)
                }
                .font(Theme.rowNameFont)
                .accessibilityElement(children: .combine)

                Divider()
                Text(power.chargingExplanation)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Read-only diagnostics. Change power settings in macOS System Settings.")
                    .font(Theme.smallCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Sources and limits", isExpanded: $sourcesExpanded) {
                    HardwareTelemetryNotesView()
                        .padding(.top, 8)
                }
                .font(Theme.captionFont)
                .tint(Theme.textSecondary)
                .accessibilityHint(
                    "Explains collection scope and hardware-dependent readings; does not enable monitoring or request access."
                )
            }
        }
    }
}

struct HardwareTelemetryNotesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(HardwareTelemetryNote.allCases) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title).font(Theme.rowNameFont).foregroundStyle(Theme.textPrimary)
                    Text(note.scopeLabel).font(Theme.smallCaption).foregroundStyle(Theme.textSecondary)
                    Text(note.explanation).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
