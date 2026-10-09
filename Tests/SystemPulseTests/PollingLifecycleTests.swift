import Darwin
import XCTest

@testable import SystemPulse

private final class WeakStoreReference {
    weak var value: MonitorStore?
    init(_ value: MonitorStore?) { self.value = value }
}

final class PollingLifecycleTests: XCTestCase {
    func testInactivePreviewNeverStartsThroughWake() {
        var lifecycle = PollingLifecycle(enabled: false)
        XCTAssertFalse(lifecycle.suspend())
        XCTAssertFalse(lifecycle.resume())
        XCTAssertFalse(lifecycle.accepts(lifecycle.generation))
        XCTAssertEqual(lifecycle.state, .inactive)
    }

    func testSuspendAndResumeRejectAllOldInFlightResults() {
        var lifecycle = PollingLifecycle(enabled: true)
        let beforeSleep = lifecycle.generation
        XCTAssertTrue(lifecycle.accepts(beforeSleep))
        XCTAssertTrue(lifecycle.suspend())
        XCTAssertFalse(lifecycle.accepts(beforeSleep))
        let sleeping = lifecycle.generation
        XCTAssertFalse(lifecycle.suspend())
        XCTAssertEqual(lifecycle.generation, sleeping)
        XCTAssertTrue(lifecycle.resume())
        XCTAssertFalse(lifecycle.accepts(beforeSleep))
        XCTAssertFalse(lifecycle.accepts(sleeping))
        XCTAssertTrue(lifecycle.accepts(lifecycle.generation))
        XCTAssertFalse(lifecycle.resume())
    }

    func testStopIsTerminalFromEveryState() {
        for enabled in [false, true] {
            for suspend in [false, true] {
                var lifecycle = PollingLifecycle(enabled: enabled)
                if suspend { lifecycle.suspend() }
                let old = lifecycle.generation
                lifecycle.stop()
                let stopped = lifecycle.generation
                XCTAssertFalse(lifecycle.accepts(old))
                XCTAssertFalse(lifecycle.resume())
                XCTAssertFalse(lifecycle.suspend())
                lifecycle.stop()
                XCTAssertEqual(lifecycle.generation, stopped)
                XCTAssertEqual(lifecycle.state, .stopped)
            }
        }
    }

    @MainActor
    func testStoreShutdownIsIdempotentAndWakeCannotResurrectIt() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        XCTAssertEqual(store.pollingState, .inactive)
        store.stopPolling()
        let stoppedRevision = store.notificationAuthorizationRevision
        store.stopPolling()
        XCTAssertEqual(store.notificationAuthorizationRevision, stoppedRevision)
        store.resumePolling()
        store.restartPolling()
        store.isPanelVisible = true
        await Task.yield()
        XCTAssertEqual(store.pollingState, .stopped)
        XCTAssertTrue(store.cpuHistory.isEmpty)
        XCTAssertTrue(store.volumes.isEmpty)
    }

    @MainActor
    func testPendingToastDoesNotRetainStore() async throws {
        let fixture = try SettingsPreferencesFixture()
        var store: MonitorStore? = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        let weakStore = WeakStoreReference(store)
        store?.showToast("Disposable toast")
        store = nil
        await Task.yield()
        XCTAssertNil(weakStore.value, "An idle toast task must not keep a discarded store alive for 2.2 seconds")
    }

    func testCounterSuspensionKeepsObservedTotalsButResetsRateBaseline() {
        var tracker = CounterRateTracker()
        let base = Date(timeIntervalSince1970: 1000)
        tracker.apply(["fixture": ByteCounters(first: 100, second: 200)], at: base)
        tracker.apply(["fixture": ByteCounters(first: 130, second: 260)], at: base.addingTimeInterval(3))
        tracker.resetBaseline()
        XCTAssertEqual(tracker.firstTotal, 30)
        XCTAssertEqual(tracker.secondTotal, 60)
        XCTAssertEqual(tracker.firstRate, 0)
        tracker.apply(["fixture": ByteCounters(first: 50_000, second: 60_000)], at: base.addingTimeInterval(300))
        XCTAssertEqual(tracker.firstTotal, 30, "Suspended/unobserved bytes are not invented as a wake sample")
        XCTAssertEqual(tracker.firstRate, 0)
        tracker.apply(["fixture": ByteCounters(first: 50_030, second: 60_060)], at: base.addingTimeInterval(303))
        XCTAssertEqual(tracker.firstRate, 10)
        XCTAssertEqual(tracker.firstTotal, 60)
    }

    func testInterfaceSuspensionPreservesIdentityAndTotals() {
        func snapshot(_ bytes: UInt64) -> NetworkInterfaceSnapshot {
            NetworkInterfaceSnapshot(
                name: "en0", displayName: "Fixture", addresses: [], isActive: true, kind: .wifi, bytesIn: bytes,
                bytesOut: bytes)
        }
        var tracker = NetworkInterfaceTracker()
        let base = Date(timeIntervalSince1970: 1000)
        tracker.apply([snapshot(100)], at: base)
        tracker.apply([snapshot(130)], at: base.addingTimeInterval(3))
        tracker.resetBaselines()
        XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 30)
        tracker.apply([snapshot(50_000)], at: base.addingTimeInterval(300))
        XCTAssertEqual(tracker.interfaces.first?.id, "en0")
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 30)
        XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
    }

    @MainActor
    func testCPUBaselineCannotRearmALatchedAlert() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        preferences.alertsEnabled = true
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: preferences, alertSink: { events.append($0) })
        store.notificationDeliveryAllowed = true
        let base = Date(timeIntervalSince1970: 1000)
        func sample(_ second: Int, baseline: Bool = false) {
            let date = base.addingTimeInterval(Double(second))
            store.applySample(
                cpu: .init(perCore: [baseline ? 0 : 95], hasInterval: !baseline),
                memory: MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: 0),
                io: DiskIOSnapshot(timestamp: date), power: nil, net: NetworkSnapshot(timestamp: date),
                disk: nil, info: nil, evaluatedAt: date)
        }
        for second in stride(from: 0, through: 30, by: 3) { sample(second) }
        XCTAssertEqual(events.count, 1)
        let observedCPUHistory = store.cpuHistory
        sample(1800, baseline: true)
        XCTAssertEqual(store.cpuHistory, observedCPUHistory, "Baseline zero is not an observed CPU interval")
        XCTAssertNil(store.menuBarReadings(at: base.addingTimeInterval(1800)).cpuPercent)
        XCTAssertNil(store.alertMeasurements(at: base.addingTimeInterval(1800))[.cpuUsage])
        XCTAssertFalse(store.hasCPUReading)
        XCTAssertTrue(store.snapshotText(at: base.addingTimeInterval(1800)).contains("CPU: Unavailable"))
        XCTAssertNil(store.diagnosticSnapshot(capturedAt: base.addingTimeInterval(1800)).cpuPercent)
        XCTAssertEqual(store.cpuTimeline.latestTimestamp, base.addingTimeInterval(30))
        for second in stride(from: 1803, through: 1863, by: 3) { sample(second) }
        XCTAssertEqual(events.count, 1, "A wake baseline is unknown, not a low CPU recovery reading")
    }

    @MainActor
    func testFailedOrTruncatedMemoryQueryStaysUnavailableForAlerts() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        let sampler = SystemSampler()
        let failed = sampler.memoryBreakdown(query: { _, _ in KERN_FAILURE })
        let truncated = sampler.memoryBreakdown(query: { _, count in
            count = 1
            return KERN_SUCCESS
        })
        for (index, memory) in [failed, truncated].enumerated() {
            let date = Date(timeIntervalSince1970: 1000 + Double(index) * 3)
            store.applySample(
                cpu: .init(perCore: [10]), memory: memory,
                io: DiskIOSnapshot(timestamp: date), power: nil, net: NetworkSnapshot(timestamp: date),
                disk: nil, info: nil, evaluatedAt: date)
            XCTAssertEqual(memory.total, 0)
            XCTAssertTrue(store.snapshotText(at: date).contains("Memory: Unavailable"))
            XCTAssertNil(store.menuBarReadings(at: date).memoryPercent)
            XCTAssertNil(store.alertMeasurements(at: date)[.memoryHeadroom])
            XCTAssertTrue(store.memoryTimeline.points(in: .fiveMinutes, endingAt: date).isEmpty)
        }
    }

    func testAlertInterruptPreservesLatchAndCooldownButRestartsWarmup() {
        var coordinator = AlertCoordinator()
        let base = Date(timeIntervalSince1970: 1000)
        let rule = AlertRule(kind: .cpuUsage)
        func evaluate(_ second: Int, _ value: Double) -> [AlertEvent] {
            let date = base.addingTimeInterval(Double(second))
            return coordinator.evaluate(
                [.cpuUsage: SampledAlertValue(value: value, sampledAt: date)], at: date, rules: [rule], enabled: true)
        }
        for second in stride(from: 0, through: 27, by: 3) { XCTAssertTrue(evaluate(second, 95).isEmpty) }
        coordinator.interrupt()
        for second in stride(from: 300, through: 327, by: 3) { XCTAssertTrue(evaluate(second, 95).isEmpty) }
        XCTAssertEqual(evaluate(330, 95).count, 1)
        coordinator.interrupt()
        for second in stride(from: 1800, through: 1860, by: 3) {
            XCTAssertTrue(evaluate(second, 95).isEmpty, "Wake is not recovery, even after cooldown")
        }
        XCTAssertTrue(evaluate(1863, 10).isEmpty)
        for second in stride(from: 1866, through: 1893, by: 3) { XCTAssertTrue(evaluate(second, 95).isEmpty) }
        XCTAssertEqual(evaluate(1896, 95).count, 1)
    }
}
