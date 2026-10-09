import Foundation

/// Bounds AppDelegate's authorization-refresh waiters, not the service's shared OS query.
@MainActor
final class NotificationAuthorizationRefresh {
    static let interval: TimeInterval = 60

    private let now: @MainActor () -> Date
    private let refresh: @MainActor () async -> Void
    private let onComplete: @MainActor () -> Void
    private var lastRequestedAt: Date?
    private var inFlight: Task<Void, Never>?
    private var isStopped = false

    init(
        now: @escaping @MainActor () -> Date = { .now },
        refresh: @escaping @MainActor () async -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.now = now
        self.refresh = refresh
        self.onComplete = onComplete
    }

    /// True only when a new waiter was scheduled. Wake requests bypass cadence,
    /// but never a pending waiter or terminal stop. Ignored requests are not queued.
    @discardableResult
    func request(force: Bool = false) -> Bool {
        guard !isStopped, inFlight == nil else { return false }
        let date = now()
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
        if !force, let lastRequestedAt {
            let elapsed = date.timeIntervalSince(lastRequestedAt)
            guard elapsed.isFinite, elapsed >= 0 else {
                // Rebase a future baseline after a clock rollback without querying.
                // Repeated malformed/retrograde readings must not cause query spam.
                self.lastRequestedAt = date
                return false
            }
            guard elapsed >= Self.interval else { return false }
        }
        lastRequestedAt = date
        // Copy the operation, never promote weak self across its suspension.
        // Cancelling this waiter does not cancel the service's underlying shared query.
        inFlight = Task { [weak self, refresh] in
            guard !Task.isCancelled else { return }
            await refresh()
            self?.completeRefresh()
        }
        return true
    }

    private func completeRefresh() {
        inFlight = nil
        guard !isStopped, !Task.isCancelled else { return }
        onComplete()
    }

    /// Terminal: cancellation may not interrupt an OS callback, so completion is guarded too.
    func stop() {
        isStopped = true
        inFlight?.cancel()
    }

    /// Waits for the currently scheduled waiter only; does not schedule or retry work.
    func waitForCurrentRefresh() async {
        await inFlight?.value
    }

    deinit {
        inFlight?.cancel()
    }
}
