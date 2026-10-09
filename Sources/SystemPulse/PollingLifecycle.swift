/// A stopped store is terminal; suspension is reversible only for a store that
/// opted into automatic polling. Generation tokens reject pre-sleep results.
struct PollingLifecycle {
    enum State: Equatable { case inactive, running, suspended, stopped }
    private(set) var state: State
    private(set) var generation: UInt64 = 0
    var isRunning: Bool { state == .running }

    init(enabled: Bool) { state = enabled ? .running : .inactive }

    @discardableResult
    mutating func suspend() -> Bool {
        guard state == .running else { return false }
        state = .suspended
        generation &+= 1
        return true
    }

    @discardableResult
    mutating func resume() -> Bool {
        guard state == .suspended else { return false }
        state = .running
        generation &+= 1
        return true
    }

    mutating func stop() {
        guard state != .stopped else { return }
        state = .stopped
        generation &+= 1
    }

    func accepts(_ token: UInt64) -> Bool { isRunning && token == generation }
}
