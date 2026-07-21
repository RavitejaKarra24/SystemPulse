import SwiftUI

struct DiskGaugeCard: View {
    let store: MonitorStore

    private var accent: Color { Theme.accent(for: .disk) }
    private var usageFraction: CGFloat {
        CGFloat(min(store.diskUsage, 100)) / 100
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.12), lineWidth: 18)
                        .blur(radius: 2)

                    Circle()
                        .stroke(Theme.trackColor, style: StrokeStyle(lineWidth: 13))

                    Circle()
                        .trim(from: 0, to: usageFraction)
                        .stroke(
                            Theme.ringGradient(for: .disk),
                            style: StrokeStyle(lineWidth: 13, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: accent.opacity(0.45), radius: 6, y: 0)
                        .animation(Theme.smoothSpring, value: store.diskUsage)

                    VStack(spacing: 1) {
                        Text("\(Int(store.diskUsage))%")
                            .font(Theme.bigValueFont)
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("used")
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 12) {
                    statRow("Total Capacity", ByteFormatter.format(store.diskTotal), color: Theme.textPrimary)
                    statRow("Used Space", ByteFormatter.format(store.diskUsed), color: accent)
                    statRow("Free Space", ByteFormatter.format(store.diskFree), color: Theme.accentGreen)

                    if store.reclaimableBytes > 0 {
                        statRow("Reclaimable", ByteFormatter.format(store.reclaimableBytes), color: Theme.accentOrange)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func statRow(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.valueFont)
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

struct ScanStatusBar: View {
    let store: MonitorStore

    var body: some View {
        Group {
            if store.isScanning {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                        Text(store.scanCurrentPath.isEmpty ? "Scanning…" : shortPath(store.scanCurrentPath))
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(Int(store.scanProgress * 100))%")
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.trackColor)
                            Capsule()
                                .fill(Theme.pillGradient(for: .disk))
                                .frame(width: max(6, geo.size.width * store.scanProgress))
                                .animation(Theme.quickSpring, value: store.scanProgress)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(insetCapsule)
            } else if store.lastScanComplete {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accentGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Scan Complete")
                            .font(Theme.rowNameFont)
                            .foregroundStyle(Theme.accentGreen)
                        if store.reclaimableBytes > 0 {
                            Text("\(ByteFormatter.format(store.reclaimableBytes)) reclaimable")
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                    Button {
                        store.scanDisk()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Scan again")
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .background(insetCapsule)
            } else {
                Button {
                    store.scanDisk()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Scan for Reclaimable Space")
                    }
                    .font(Theme.rowNameFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule()
                            .fill(Theme.pillGradient(for: .disk))
                            .shadow(color: Theme.accentOrange.opacity(0.35), radius: 8, y: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var insetCapsule: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.insetFill)
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.insetStroke, lineWidth: 1)
        }
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

/// Expandable Applications / Development / System categories with inline delete.
struct DiskCategoryListCard: View {
    let store: MonitorStore
    let onSelectItem: (DiskItem) -> Void
    @State private var expanded: Set<String> = ["development", "applications"]
    @State private var pendingDeleteId: String?

    var body: some View {
        if store.diskCategories.isEmpty {
            if store.isScanning {
                GlassCard(padding: 20) {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Discovering reclaimable space…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyView()
            }
        } else {
            GlassCard(padding: 8) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.diskCategories.enumerated()), id: \.element.id) { index, category in
                            if index > 0 {
                                Rectangle()
                                    .fill(Theme.dividerColor)
                                    .frame(height: 1)
                                    .padding(.horizontal, 6)
                            }
                            categoryRow(category)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func categoryRow(_ category: DiskCategory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(Theme.quickSpring) {
                        if expanded.contains(category.id) { expanded.remove(category.id) }
                        else { expanded.insert(category.id) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(expanded.contains(category.id) ? 90 : 0))
                            .frame(width: 14)

                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accentOrange.opacity(0.14))
                            Image(systemName: category.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.accentOrange)
                        }
                        .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.name)
                                .font(Theme.rowNameFont)
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(category.items.count) items")
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Spacer()

                        Text(category.sizeFormatted)
                            .font(Theme.rowValueFont)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)

            if expanded.contains(category.id) {
                VStack(spacing: 2) {
                    ForEach(category.items) { item in
                        itemRow(item)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func itemRow(_ item: DiskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                onSelectItem(item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.safeToDelete ? "folder.fill" : "folder.badge.questionmark")
                        .font(.system(size: 12))
                        .foregroundStyle(item.safeToDelete ? Theme.accentOrange.opacity(0.85) : Theme.accentYellow)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(item.fileCount) files")
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Text(item.sizeFormatted)
                        .font(Theme.smallCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if pendingDeleteId == item.id {
                Button("Confirm") {
                    _ = store.deleteDiskItem(item)
                    pendingDeleteId = nil
                }
                .buttonStyle(.plain)
                .font(Theme.smallCaption.weight(.bold))
                .foregroundStyle(Theme.accentRed)

                Button {
                    pendingDeleteId = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    pendingDeleteId = item.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Move to Trash")
            }
        }
        .padding(.leading, 38)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .contextMenu {
            Button("Show Details") { onSelectItem(item) }
            Button("Show in Finder") { store.revealInFinder(path: item.path) }
            Divider()
            Button("Move to Trash", role: .destructive) {
                _ = store.deleteDiskItem(item)
            }
        }
    }
}
