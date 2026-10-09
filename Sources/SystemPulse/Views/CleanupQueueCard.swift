import SwiftUI

struct CleanupQueueCard: View {
    let store: MonitorStore

    var body: some View {
        if !store.cleanupQueue.isEmpty || store.isPerformingCleanup || !store.cleanupResults.isEmpty {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Reviewed cleanup queue").font(Theme.rowNameFont)
                        Spacer()
                        if store.isPerformingCleanup {
                            Button(store.isStoppingCleanup ? "Stopping…" : "Stop") { store.stopCleanup() }
                                .disabled(store.isStoppingCleanup)
                                .controlSize(.small)
                                .help("Finish the current filesystem call; skip remaining locations.")
                        } else {
                            Button("Clear") { store.clearCleanupQueue() }
                                .controlSize(.small)
                                .disabled(store.cleanupQueue.isEmpty)
                        }
                    }
                    Text(
                        "\(store.cleanupQueue.count) queued · \(ByteFormatter.format(CleanupQueue.totalBytes(store.cleanupQueue))) logical size, not guaranteed recovery. Nothing moves until you review and confirm."
                    )
                    .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if !store.cleanupQueue.isEmpty {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(store.cleanupQueue) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(Theme.captionFont)
                                            Text(item.sizeFormatted).font(Theme.smallCaption).foregroundStyle(
                                                Theme.textSecondary)
                                        }
                                        Spacer()
                                        Button {
                                            store.removeQueuedCleanupItem(item.id)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(store.isPerformingCleanup)
                                        .accessibilityLabel("Remove \(item.name) from cleanup queue")
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: min(CGFloat(store.cleanupQueue.count) * 40, 160))
                        Button("Review Queue…") { CleanupReviewWindowController.shared.present(store: store) }
                            .buttonStyle(.bordered)
                            .disabled(store.cleanupIsBlocked)
                            .accessibilityHint("Opens an itemized review window. No files are moved yet.")
                    }
                    if store.isPerformingCleanup {
                        ProgressView("Processing reviewed locations…")
                            .controlSize(.small)
                    }
                    CleanupResultsView(results: store.cleanupResults)
                    if !store.isPerformingCleanup && !store.cleanupResults.isEmpty {
                        Button("Dismiss Results") { store.clearCleanupResults() }.controlSize(.small)
                    }
                    Text(
                        "Trash only. Use Finder’s Put Back where available; SystemPulse does not promise an automatic Undo. Failed or skipped locations stay queued; retry requires a new review and confirmation."
                    )
                    .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct CleanupResultsView: View {
    let results: [CleanupItemResult]
    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Per-location results").font(Theme.rowNameFont)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.item.name).font(Theme.captionFont)
                                Text(result.outcome.message).font(Theme.smallCaption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: min(CGFloat(results.count) * 50, 180))
            }
        }
    }
}

struct CleanupReviewView: View {
    let store: MonitorStore
    let review: CleanupReview
    let onClose: () -> Void
    @State private var confirmation = false

    private var isThisRun: Bool { store.cleanupRunID == review.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review cleanup").font(.title2.weight(.semibold))
            Text("\(review.items.count) locations · \(ByteFormatter.format(review.logicalBytes)) measured logical size")
                .font(.headline)
            Text(
                "Quit apps using these locations first. Cache data may need to be rebuilt or downloaded. Measurements are not guaranteed physical space recovery. SystemPulse uses Trash only, never permanent deletion or privilege escalation."
            )
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(review.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name).font(.headline)
                                Spacer()
                                Text(item.sizeFormatted).monospacedDigit()
                            }
                            Text(item.path).font(.caption).textSelection(.enabled)
                            Text(DiskTrashConfirmation.safetyMessage(for: item)).font(.caption).foregroundStyle(
                                .secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: .infinity)
            if isThisRun {
                if store.isPerformingCleanup {
                    ProgressView(
                        store.isStoppingCleanup
                            ? "Stopping after current location…" : "Moving reviewed locations to Trash…")
                }
                CleanupResultsView(results: store.cleanupResults)
            } else if !store.canConfirmCleanup(review) {
                Text(
                    "This review is no longer current. Return to a complete cleanup scan and prepare a new review; no new locations can be moved from this window."
                )
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("Restore manually with Finder’s Put Back where available. No automatic Undo is promised.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(isThisRun ? "Close" : "Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isThisRun && store.isPerformingCleanup {
                    Button(store.isStoppingCleanup ? "Stopping…" : "Stop Remaining") { store.stopCleanup() }
                        .disabled(store.isStoppingCleanup)
                } else if !isThisRun {
                    Button("Move Reviewed Items to Trash…", role: .destructive) { confirmation = true }
                        .disabled(!store.canConfirmCleanup(review))
                }
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 620)
        .alert("Move \(review.items.count) reviewed locations to Trash?", isPresented: $confirmation) {
            Button("Move to Trash", role: .destructive) {
                if !store.confirmCleanup(review) {
                    store.showToast("Cleanup review expired or a location changed", isError: true)
                }
            }
            .disabled(!store.canConfirmCleanup(review))
            .keyboardShortcut(DestructiveConfirmationKeyboard.destructiveShortcut)
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(DestructiveConfirmationKeyboard.cancelShortcut)
        } message: {
            Text(
                "Only the itemized locations in this review are included. This cannot be undone automatically. Cancel leaves everything unchanged."
            )
        }
    }
}
