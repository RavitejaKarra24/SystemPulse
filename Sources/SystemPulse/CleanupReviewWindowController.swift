import AppKit
import SwiftUI

/// App-lifetime owner: dismissing the transient monitoring popover does not
/// discard the itemized review or per-location results. One review window only.
@MainActor
final class CleanupReviewWindowController: NSObject, NSWindowDelegate {
    static let shared = CleanupReviewWindowController()
    private(set) var window: NSWindow?
    private var store: MonitorStore?
    private var review: CleanupReview?

    func present(store: MonitorStore) {
        if self.store === store, let review,
            (store.isPerformingCleanup && store.cleanupRunID == review.id) || store.canConfirmCleanup(review)
        {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        close()
        guard let review = store.prepareCleanupReview() else {
            store.showToast("Queue changed or a location is no longer eligible · review the scan again", isError: true)
            return
        }
        self.store = store
        self.review = review
        let content = CleanupReviewView(store: store, review: review, onClose: { [weak self] in self?.close() })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 630),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Review Cleanup — SystemPulse"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 540, height: 640)
        window.delegate = self
        window.contentView = NSHostingView(rootView: content)
        self.window = window
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        finish()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        if let store, let review { store.dismissCleanupReview(review) }
        window = nil
        store = nil
        review = nil
    }
}
