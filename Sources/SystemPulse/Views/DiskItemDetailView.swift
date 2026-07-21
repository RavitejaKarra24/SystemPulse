import AppKit
import SwiftUI

struct DiskItemDetailView: View {
    let store: MonitorStore
    let itemId: String
    let onBack: () -> Void
    let onDeleted: () -> Void

    @State private var confirmDelete = false

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
                    Image(systemName: item.safeToDelete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(item.safeToDelete ? Theme.accentGreen : Theme.accentOrange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.safeToDelete ? "Safe to Delete" : "Review Before Deleting")
                            .font(Theme.rowNameFont)
                            .foregroundStyle(item.safeToDelete ? Theme.accentGreen : Theme.accentOrange)
                        Text(item.safetyNote)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((item.safeToDelete ? Theme.accentGreen : Theme.accentOrange).opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    (item.safeToDelete ? Theme.accentGreen : Theme.accentOrange).opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                )

                HStack(spacing: 10) {
                    OutlinePillButton(title: "Show in Finder") {
                        store.revealInFinder(path: item.path)
                    }
                    FilledPillButton(
                        title: confirmDelete ? "Confirm Delete" : "Delete",
                        color: confirmDelete ? Theme.accentRed : Theme.accentOrange
                    ) {
                        if confirmDelete {
                            if store.deleteDiskItem(item) {
                                onDeleted()
                            }
                        } else {
                            confirmDelete = true
                        }
                    }
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
    }
}
