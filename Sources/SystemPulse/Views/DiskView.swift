import SwiftUI

struct DiskGaugeCard: View {
    let store: MonitorStore
    var volume: MonitoredVolume? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { Theme.accent(for: .disk) }
    private var totalCapacity: UInt64? {
        volume.map(\.totalBytes) ?? (store.diskTotal > 0 ? store.diskTotal : nil)
    }
    private var availableCapacity: UInt64? {
        volume.map(\.availableBytes) ?? (store.diskTotal > 0 ? store.diskFree : nil)
    }
    private var usedCapacity: UInt64? {
        guard let totalCapacity, let availableCapacity else { return nil }
        return totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
    }
    private var usageFraction: CGFloat {
        guard let totalCapacity, totalCapacity > 0, let usedCapacity else { return 0 }
        return CGFloat(Double(usedCapacity) / Double(totalCapacity))
    }
    private func capacityLabel(_ bytes: UInt64?) -> String {
        bytes.map(ByteFormatter.format) ?? "Unavailable"
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Theme.trackColor, style: StrokeStyle(lineWidth: 10))

                    Circle()
                        .trim(from: 0, to: usageFraction)
                        .stroke(
                            Theme.ringGradient(for: .disk),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : Theme.smoothSpring, value: usageFraction)

                    VStack(spacing: 1) {
                        Text(
                            usedCapacity == nil || totalCapacity == 0
                                ? "—" : String(format: "%.0f%%", usageFraction * 100)
                        )
                        .font(Theme.bigValueFont)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        Text("used")
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 12) {
                    statRow("Total Capacity", capacityLabel(totalCapacity), color: Theme.textPrimary)
                    statRow("Estimated Used", capacityLabel(usedCapacity), color: accent)
                    statRow("Available Space", capacityLabel(availableCapacity), color: Theme.accentGreen)
                }
                Spacer(minLength: 0)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
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
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
    }
}

struct ScanStatusBar: View {
    let store: MonitorStore
    @State private var folderSelection = FolderSelectionSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard store.scanProgress.isFinite else { return 0 }
        return min(1, max(0, store.scanProgress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.scanScope.isReadOnly ? "Folder inventory" : "Cleanup locations")
                    .font(Theme.rowNameFont)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Choose Folder…") { folderSelection.present(for: store) }
                    .controlSize(.small)
                    .disabled(
                        store.isScanning || store.isChoosingScanFolder || store.isPerformingCleanup
                            || folderSelection.isPresenting
                            || store.pollingState == .stopped
                    )
                    .accessibilityHint(
                        "Choose a local folder for a read-only scan. Folder selection does not enable cleanup.")
            }
            if let root = store.scanScope.folderURL {
                Text(shortPath(root.path))
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(root.path)
                HStack(alignment: .top) {
                    Text("Read-only · logical file sizes, not space recovered")
                        .font(Theme.smallCaption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 6)
                    Button("Cleanup locations") { store.scanCleanupLocations() }
                        .controlSize(.small)
                        .disabled(
                            store.isScanning || store.isChoosingScanFolder || store.isPerformingCleanup
                                || store.pollingState == .stopped
                        )
                        .help("Switch back and scan only the known home-folder cleanup locations.")
                }
            }
            scanStatus
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var scanStatus: some View {
        Group {
            if store.isChoosingScanFolder {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Choosing a folder…")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if store.isScanning {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                        Text(
                            store.isCancellingScan
                                ? "Stopping scan…"
                                : (store.scanCurrentPath.isEmpty ? "Scanning…" : shortPath(store.scanCurrentPath))
                        )
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Spacer()
                        if !store.scanScope.isReadOnly {
                            Text("\(Int(progress * 100))%")
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                                .help("Progress counts planned locations, not bytes or remaining time.")
                        }
                        Button("Cancel") { store.cancelDiskScan() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(store.isCancellingScan)
                            .accessibilityLabel(
                                store.scanScope.isReadOnly ? "Cancel folder inventory" : "Cancel cleanup scan"
                            )
                            .help("Stops after the current filesystem call returns. Partial results are read-only.")
                    }

                    if !store.scanScope.isReadOnly {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.trackColor)
                                Capsule()
                                    .fill(Theme.pillGradient(for: .disk))
                                    .frame(width: geo.size.width * progress)
                                    .animation(reduceMotion ? nil : Theme.quickSpring, value: progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(insetCapsule)
            } else if store.lastScanComplete || store.lastScanCancelled {
                HStack(spacing: 6) {
                    Image(systemName: store.scanResultsArePartial ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(store.scanResultsArePartial ? Theme.accentYellow : Theme.accentGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(
                            store.lastScanCancelled
                                ? "Scan stopped" : (store.scanResultsArePartial ? "Partial scan" : "Scan Complete")
                        )
                        .font(Theme.rowNameFont)
                        .foregroundStyle(Theme.textPrimary)
                        Text(scanSummary)
                            .font(Theme.smallCaption)
                            .foregroundStyle(Theme.textTertiary)
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
                    .accessibilityLabel(
                        store.scanScope.isReadOnly ? "Scan selected folder again" : "Scan cleanup locations again"
                    )
                    .disabled(store.pollingState == .stopped || store.isPerformingCleanup)
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
                        Text("Scan Cleanup Locations")
                    }
                    .font(Theme.rowNameFont)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(insetCapsule)
                }
                .buttonStyle(.plain)
                .disabled(store.pollingState == .stopped || store.isPerformingCleanup)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var scanSummary: String {
        if store.scanSkippedLocationCount > 0 {
            return "\(store.scanSkippedLocationCount) locations could not be measured · results are read-only"
        }
        if store.lastScanCancelled { return "Partial results only · cleanup is disabled" }
        if store.scanScope.isReadOnly {
            let bytes = store.diskCategories.first?.bytes ?? 0
            let files = store.diskCategories.first?.items.first?.fileCount ?? 0
            return "\(ByteFormatter.format(bytes)) observed · \(files) files · read-only"
        }
        return store.diskCategories.isEmpty
            ? "No cleanup items in the current results."
            : "\(ByteFormatter.format(store.reclaimableBytes)) in eligible cache locations"
    }

    private var insetCapsule: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.insetFill)
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.insetStroke, lineWidth: 1)
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

/// Expandable scan results with confirmed, user-initiated cleanup.
struct DiskCategoryListCard: View {
    let store: MonitorStore
    let onSelectItem: (DiskItem) -> Void
    @State private var expanded: Set<String> = ["development", "applications", "selected-folder"]
    @State private var pendingTrashItem: DiskTrashReview?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        scanResults
            .modifier(
                DiskTrashConfirmation(
                    item: $pendingTrashItem, cleanupIsBlocked: store.cleanupIsBlocked
                ) { item in
                    _ = store.deleteDiskItem(item)
                }
            )
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }

    @ViewBuilder
    private var scanResults: some View {
        if store.diskCategories.isEmpty {
            if store.isScanning {
                GlassCard(padding: 20) {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            store.scanScope.isReadOnly
                                ? "Measuring selected folder…" : "Checking known cleanup locations…"
                        )
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if store.lastScanComplete || store.lastScanCancelled {
                GlassCard(padding: 20) {
                    VStack(spacing: 8) {
                        Text(store.scanResultsArePartial ? "Scan results are incomplete" : "No cleanup items to show")
                            .font(Theme.rowNameFont)
                            .foregroundStyle(Theme.textPrimary)
                        Text(
                            store.scanResultsArePartial
                                ? "The scan stopped or some locations could not be measured. Scan again to obtain complete results; cleanup is disabled."
                                : "No items remain in the current results. This targeted scan checks known cache and support locations, not the entire disk."
                        )
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            GlassCard(padding: 8) {
                Group {
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
            }
        }
    }

    @MainActor
    private func categoryRow(_ category: DiskCategory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.quickSpring) {
                        if expanded.contains(category.id) {
                            expanded.remove(category.id)
                        } else {
                            expanded.insert(category.id)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(expanded.contains(category.id) ? 90 : 0))
                            .frame(width: 14)
                            .accessibilityHidden(true)

                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accentOrange.opacity(0.14))
                            Image(systemName: category.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.accentOrange)
                                .accessibilityHidden(true)
                        }
                        .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.name)
                                .font(Theme.rowNameFont)
                                .foregroundStyle(Theme.textPrimary)
                            Text(category.items.count == 1 ? "1 item" : "\(category.items.count) items")
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
                .accessibilityValue(expanded.contains(category.id) ? "Expanded" : "Collapsed")
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

    @MainActor
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
                        .accessibilityHidden(true)

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

            Button {
                _ = store.queueCleanupItem(item)
            } label: {
                Image(systemName: store.cleanupQueue.contains(item) ? "checkmark.circle.fill" : "plus.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.cleanupIsBlocked || !item.safeToDelete || store.cleanupQueue.contains(item))
            .accessibilityLabel("Add \(item.name) to reviewed cleanup queue")
            .help("Queue for itemized review; nothing is moved yet.")

            Button(role: .destructive) {
                pendingTrashItem = store.prepareDiskTrashReview(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.cleanupIsBlocked || !item.safeToDelete)
            .help(
                store.scanScope.isReadOnly
                    ? "Folder inventory is read-only"
                    : store.scanResultsArePartial
                        ? "Partial scan results are read-only"
                        : (item.safeToDelete ? "Move to Trash" : "Protected data · review in Finder")
            )
            .accessibilityLabel("Move \(item.name) to Trash")
        }
        .padding(.leading, 38)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .contextMenu {
            Button("Show Details") { onSelectItem(item) }
            Button("Show in Finder") { store.revealInFinder(path: item.path) }
            Divider()
            Button("Add to Cleanup Queue") { _ = store.queueCleanupItem(item) }
                .disabled(store.cleanupIsBlocked || !item.safeToDelete || store.cleanupQueue.contains(item))
            Button("Move to Trash…", role: .destructive) {
                pendingTrashItem = store.prepareDiskTrashReview(item)
            }
            .disabled(store.cleanupIsBlocked || !item.safeToDelete)
        }
    }
}

/// Shared by every cleanup entry point so a context menu cannot bypass review.
struct DiskTrashConfirmation: ViewModifier {
    @Binding var item: DiskTrashReview?
    let cleanupIsBlocked: Bool
    let onConfirm: (DiskTrashReview) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Move “\(item?.item.name ?? "Item")” to Trash?",
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            presenting: item
        ) { item in
            Button("Move to Trash", role: .destructive) {
                onConfirm(item)
            }
            .disabled(cleanupIsBlocked || !item.item.safeToDelete)
            .keyboardShortcut(DestructiveConfirmationKeyboard.destructiveShortcut)
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(DestructiveConfirmationKeyboard.cancelShortcut)
        } message: { item in
            Text(Self.safetyMessage(for: item.item))
        }
    }

    static func safetyMessage(for item: DiskItem) -> String {
        // Preserve the scanner's explanation without its blanket safety claim.
        let note = item.safetyNote.replacingOccurrences(of: "Safe to clear; ", with: "")
        let caution =
            item.safeToDelete
            ? "Cleanup is not risk-free. Quit apps using this item first. Removed data may need to be rebuilt or downloaded again."
            : "Cleanup is disabled for this item. Review it in Finder."
        return "\(note)\n\n\(caution)"
    }
}
