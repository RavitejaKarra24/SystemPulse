import SwiftUI

/// Selection changes monitoring only. Scan scope and removal feedback belong to the owner.
struct VolumePickerCard: View {
    let volumes: [MonitoredVolume]
    @Binding var selection: String?

    private var selectedVolume: MonitoredVolume? {
        VolumeSelection.resolve(selectedID: selection, in: volumes)
    }

    /// Present a valid picker tag without silently clearing a removed preference.
    private var resolvedSelection: Binding<String?> {
        Binding(get: { selectedVolume?.id }, set: { selection = $0 })
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if volumes.isEmpty {
                    Label("No mounted volumes available", systemImage: "externaldrive.badge.questionmark")
                        .font(Theme.rowNameFont)
                        .foregroundStyle(Theme.textPrimary)
                    note("Volume metadata may be temporarily unavailable. Monitoring resumes when a volume appears.")
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            heading
                            picker
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            heading
                            picker
                        }
                    }
                    if let volume = selectedVolume {
                        volumeDetails(volume)
                    }
                }

                Divider()
                note("APFS volumes share space; their capacities are not additive.")
                note(
                    "Cleanup still scans your home folder. Scan sizes are logical, not guaranteed space recovered."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heading: some View {
        Text("Monitored volume")
            .font(Theme.rowNameFont)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize()
    }

    private var picker: some View {
        Picker("Monitored volume", selection: resolvedSelection) {
            ForEach(volumes) { volume in
                Text("\(volume.name) · \(locationDescription(volume))\(volume.isReadOnly ? " · Read-only" : "")")
                    .tag(Optional(volume.id))
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Monitored volume")
        .accessibilityHint("Changes capacity monitoring, not the home-folder cleanup scan.")
    }

    private func volumeDetails(_ volume: MonitoredVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(locationDescription(volume))\(volume.isReadOnly ? " · Read-only" : "")")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
            Text(volume.mountURL.path)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if volume.availableBytes == nil {
                note("Available-space metadata is unavailable; used space cannot be estimated.")
            } else if volume.availableForImportantUsage {
                note(
                    "Availability includes space macOS can reclaim, such as purgeable APFS data. Used is an estimate."
                )
            } else {
                note("Showing filesystem availability; important-usage capacity is unavailable.")
            }
            if volume.totalBytes == nil {
                note("Total-capacity metadata is unavailable.")
            }
        }
    }

    private func locationDescription(_ volume: MonitoredVolume) -> String {
        switch volume.isInternal {
        case true: return "Internal"
        case false: return "External"
        case nil: return "Connection type unavailable"
        }
    }

    private func note(_ message: String) -> some View {
        Text(message)
            .font(Theme.captionFont)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
