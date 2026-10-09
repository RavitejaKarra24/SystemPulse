import SwiftUI

struct DiskItemDetailView: View {
    let store: MonitorStore
    let itemId: String
    let onBack: () -> Void
    let onDeleted: () -> Void

    @State private var pendingTrashItem: DiskTrashReview?

    @MainActor
    private var item: DiskItem? {
        store.diskCategories.flatMap(\.items).first { $0.id == itemId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            DetailHeader(title: item?.name ?? "Item", onBack: onBack)

            if let item {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accentOrange.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.accentOrange.opacity(0.22), lineWidth: 1)
                            )
                        Image(systemName: "folder.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accentOrange)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(Theme.valueFont)
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.categoryName)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()

                    Text(item.sizeFormatted)
                        .font(Theme.heroFont)
                        .foregroundStyle(Theme.accentOrange)
                        .monospacedDigit()
                }

                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledInfoRow(label: "Total Size", value: item.sizeFormatted)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location")
                                .font(Theme.smallCaption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(item.path)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 24) {
                            LabeledInfoRow(label: "Items Found", value: "\(item.fileCount)")
                            LabeledInfoRow(label: "Category", value: item.categoryName)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.safeToDelete ? "info.circle" : "lock.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            store.scanScope.isReadOnly
                                ? "Read-only Folder Inventory"
                                : (item.safeToDelete ? "Review Before Cleanup" : "Protected Data")
                        )
                        .font(Theme.rowNameFont)
                        .foregroundStyle(Theme.textPrimary)
                        if store.scanScope.isReadOnly {
                            Text("Choosing a folder never authorizes cleanup. Scan known cleanup locations separately.")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if store.scanResultsArePartial {
                            Text("Partial scan results are read-only. Run a complete scan before cleanup.")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(DiskTrashConfirmation.safetyMessage(for: item))
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetSurface(cornerRadius: 14)

                Button("Add to Cleanup Queue") { _ = store.queueCleanupItem(item) }
                    .buttonStyle(.bordered)
                    .disabled(store.cleanupIsBlocked || !item.safeToDelete || store.cleanupQueue.contains(item))
                    .help("Nothing moves until you review and confirm the queue.")

                HStack(spacing: 10) {
                    OutlinePillButton(title: "Show in Finder") {
                        store.revealInFinder(path: item.path)
                    }
                    FilledPillButton(
                        title: "Move to Trash…",
                        color: Theme.accentRed,
                        isDestructive: true
                    ) {
                        pendingTrashItem = store.prepareDiskTrashReview(item)
                    }
                    .disabled(store.cleanupIsBlocked || !item.safeToDelete)
                    .help(
                        store.scanResultsArePartial
                            ? "Partial scan results are read-only"
                            : (item.safeToDelete
                                ? "Review cleanup before moving to Trash" : "Protected data · review in Finder"))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Item no longer exists.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .padding(Theme.outerPadding)
        .frame(width: Theme.popoverWidth)
        .modifier(
            DiskTrashConfirmation(
                item: $pendingTrashItem, cleanupIsBlocked: store.cleanupIsBlocked
            ) { item in
                if store.deleteDiskItem(item) {
                    onDeleted()
                }
            }
        )

    }
}
