import Foundation

/// Normal Quit stops future work but waits for the one uninterruptible OS call
/// already underway. Forced termination/system failure cannot be drained.
@MainActor
final class CleanupTerminationGate {
    private(set) var isPending = false
    private var task: Task<Void, Never>?

    func deferTerminationIfNeeded(store: MonitorStore, onReady: @escaping @MainActor () -> Void) -> Bool {
        if isPending { return true }
        guard store.isPerformingCleanup else { return false }
        isPending = true
        store.stopPolling()
        task = Task { @MainActor [self] in
            await store.waitForCleanup()
            task = nil
            onReady()
        }
        return true
    }
}
