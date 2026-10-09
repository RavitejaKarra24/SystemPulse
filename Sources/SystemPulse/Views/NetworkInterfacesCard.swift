import SwiftUI

/// Selection scopes the Network page. Overview, menu-bar and exported network values remain aggregate.
struct NetworkInterfacesCard: View {
    let interfaces: [NetworkInterfaceReading]
    @Binding var selection: String?
    var showsPicker = true

    private var visibleInterfaces: [NetworkInterfaceReading] {
        guard let selection else { return interfaces }
        return interfaces.filter { $0.id == selection }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                Text("Interface details")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                if showsPicker {
                    NetworkInterfacePicker(interfaces: interfaces, selection: $selection)
                }

                Text(
                    "Select a link for this page's chart and totals. Overview, menu bar and exports still show all physical interfaces."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if visibleInterfaces.isEmpty {
                    Text(
                        selection == nil
                            ? "No physical interface readings available."
                            : "This interface is no longer available. Choose All physical interfaces to view current links."
                    )
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(visibleInterfaces) { interface in
                        if selection == nil {
                            Button {
                                selection = interface.id
                            } label: {
                                compactRow(interface)
                            }
                            .buttonStyle(.plain)
                            .help("Inspect \(interface.displayName) throughput and local addresses")
                        } else {
                            NetworkInterfaceDetails(reading: interface)
                        }
                    }
                }

                Text("Active describes the local link, not Internet reachability.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Wi-Fi name not collected; local addresses need no location access.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(
                        "The network name is not read without permission. SystemPulse does not request Location Services or query the Wi-Fi name."
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compactRow(_ reading: NetworkInterfaceReading) -> some View {
        HStack(spacing: 8) {
            Image(systemName: reading.kind == .wifi ? "wifi" : "network")
                .foregroundStyle(reading.isActive ? Theme.accentTeal : Theme.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.displayName).font(Theme.rowNameFont).foregroundStyle(Theme.textPrimary)
                Text(
                    "\(reading.name) · \(!reading.isPresent ? "Disconnected" : (reading.isActive ? "Active" : "Inactive"))"
                )
                .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Text("↓ \(ByteFormatter.formatRate(reading.inRate)) · ↑ \(ByteFormatter.formatRate(reading.outRate))")
                .font(Theme.smallCaption).monospacedDigit().foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

}

struct NetworkInterfacePicker: View {
    let interfaces: [NetworkInterfaceReading]
    @Binding var selection: String?

    var body: some View {
        Picker("Interface", selection: $selection) {
            Text("All physical interfaces").tag(String?.none)
            ForEach(interfaces) { interface in
                Text(pickerLabel(interface)).tag(Optional(interface.id))
            }
            if let selection, !interfaces.contains(where: { $0.id == selection }) {
                Text("\(selection) · unavailable").tag(Optional(selection))
            }
        }
        .pickerStyle(.menu)
    }

    private func pickerLabel(_ reading: NetworkInterfaceReading) -> String {
        let name = reading.displayName == reading.name ? reading.name : "\(reading.displayName) (\(reading.name))"
        return reading.isPresent ? name : "\(name) · disconnected"
    }
}

private struct NetworkInterfaceDetails: View {
    let reading: NetworkInterfaceReading

    private var status: String {
        !reading.isPresent ? "Disconnected" : (reading.isActive ? "Active" : "Inactive")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    heading
                    Spacer(minLength: 8)
                    statusLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    heading
                    statusLabel
                }
            }
            Text("\(reading.kind.rawValue) · \(reading.name)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            throughput(label: "Download", rate: reading.inRate, total: reading.sessionBytesIn)
            throughput(label: "Upload", rate: reading.outRate, total: reading.sessionBytesOut)

            if !reading.isActive {
                Text(
                    reading.isPresent
                        ? "Link inactive. Rates are zero until it becomes active."
                        : "Link removed. Rates are zero; recent session totals are retained briefly."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Text("Local addresses")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            if reading.addresses.isEmpty {
                Text(reading.isPresent ? "No local IPv4 or IPv6 address assigned." : "No current local addresses.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(reading.addresses, id: \.self) { address in
                    Text(verbatim: address)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface()
    }

    private var heading: some View {
        Text(verbatim: reading.displayName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusLabel: some View {
        Label(status, systemImage: reading.isActive ? "checkmark.circle" : "minus.circle")
            .font(.caption)
            .foregroundStyle(reading.isActive ? Theme.accentTeal : Theme.textSecondary)
            .fixedSize()
    }

    private func throughput(label: String, rate: Double, total: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(label).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(ByteFormatter.formatRate(rate)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).foregroundStyle(Theme.textSecondary)
                    Text(ByteFormatter.formatRate(rate)).monospacedDigit()
                }
            }
            .font(.subheadline)
            Text("Session: \(ByteFormatter.format(total))")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
    }
}
