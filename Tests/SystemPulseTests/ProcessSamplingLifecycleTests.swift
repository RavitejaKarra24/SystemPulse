import Foundation
import XCTest

@testable import SystemPulse

final class ProcessSamplingLifecycleTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    @MainActor
    func testBlockedProcessPassDoesNotRetainDiscardedStore() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ProcessSamplingGate()
        defer { gate.release() }
        var store: MonitorStore? = makeStore(preferences: fixture.makePreferences(), gate: gate)
        let weakStore = ProcessWeakStoreReference(store)
        store?.refreshProcessesIfDue(at: epoch)
        await waitUntil { gate.calls == 1 }
        XCTAssertEqual(gate.calls, 1)
        store = nil
        await Task.yield()
        XCTAssertNil(weakStore.value, "A blocked detached process pass must not retain the store or its timer/history")
        gate.release()
        await waitUntil { gate.finishes == 1 }
    }

    @MainActor
    func testBlockedPassCannotOverlapAndTerminalStopRejectsLatePublication() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ProcessSamplingGate()
        defer { gate.release() }
        let store = makeStore(preferences: fixture.makePreferences(), gate: gate)
        store.refreshProcessesIfDue(at: epoch)
        await waitUntil { gate.calls == 1 }
        for second in 1...1_000 {
            store.refreshProcessesIfDue(at: epoch.addingTimeInterval(Double(second) * 15))
        }
        XCTAssertEqual(gate.calls, 1)
        store.stopPolling()
        gate.release()
        await store.waitForProcessRefresh()
        XCTAssertEqual(gate.finishes, 1)
        XCTAssertEqual(store.processSampleRevision, 0)
        XCTAssertTrue(store.processGroups.isEmpty)
        XCTAssertNil(store.latestProcessSampleAt)
        store.resumePolling()
        store.refreshProcessesIfDue(at: epoch.addingTimeInterval(20_000))
        XCTAssertEqual(gate.calls, 1)
    }

    @MainActor
    func testSuspensionRejectsOldPassAndWakeResetsNextProcessBaseline() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ProcessSamplingGate()
        defer { gate.release() }
        let store = makeStore(preferences: fixture.makePreferences(), gate: gate)
        defer { store.stopPolling() }
        store.refreshProcessesIfDue(at: epoch)
        await waitUntil { gate.calls == 1 }
        store.suspendPolling()
        store.resumePolling()
        store.refreshProcessesIfDue(at: epoch.addingTimeInterval(1_000))
        XCTAssertEqual(gate.calls, 1, "Wake cannot overlap the old in-flight process pass")
        gate.release()
        await store.waitForProcessRefresh()
        XCTAssertEqual(store.processSampleRevision, 0)
        store.refreshProcessesIfDue(at: epoch.addingTimeInterval(1_015))
        await store.waitForProcessRefresh()
        XCTAssertEqual(gate.resets, [false, true])
        XCTAssertEqual(store.processGroups.map(\.id), ["synthetic-group"])
    }

    @MainActor
    func testManualDriverRespectsHiddenCadenceAndNeverStartsInactiveOrStopped() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ProcessSamplingGate()
        gate.release()
        let preferences = fixture.makePreferences()
        let store = makeStore(preferences: preferences, gate: gate)
        defer { store.stopPolling() }
        XCTAssertTrue(store.cpuHistory.isEmpty)
        store.restartPolling()
        XCTAssertTrue(store.cpuHistory.isEmpty, "The manual driver must not invoke live telemetry on restart")
        store.refreshProcessesIfDue(at: epoch)
        await store.waitForProcessRefresh()
        XCTAssertEqual(store.processSampleRevision, 1)
        store.refreshProcessesIfDue(at: epoch.addingTimeInterval(14))
        store.refreshProcessesIfDue(at: Date(timeIntervalSinceReferenceDate: .nan))
        XCTAssertEqual(gate.calls, 1)
        store.refreshProcessesIfDue(at: epoch.addingTimeInterval(15))
        await store.waitForProcessRefresh()
        XCTAssertEqual(store.processSampleRevision, 2)
        XCTAssertEqual(gate.calls, 2)
        let inactive = MonitorStore(
            startPolling: false, preferences: preferences, automaticallySchedulesPolling: false,
            processSampler: { reset in gate.sample(reset: reset) })
        inactive.refreshProcessesIfDue(at: epoch)
        inactive.resumePolling()
        inactive.refreshProcessesIfDue(at: epoch.addingTimeInterval(1_000))
        store.stopPolling()
        store.refreshProcessesIfDue(at: epoch.addingTimeInterval(1_000))
        XCTAssertEqual(gate.calls, 2)
        XCTAssertTrue(inactive.cpuHistory.isEmpty)
    }

    @MainActor
    func testManualDriverVisibilityWakeAndPreferenceSyncNeverScheduleLiveQueries() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let gate = ProcessSamplingGate()
        gate.release()
        let store = makeStore(preferences: preferences, gate: gate)
        defer { store.stopPolling() }
        store.isPanelVisible = true
        store.refreshVolumes()
        store.suspendPolling()
        store.resumePolling()
        preferences.refreshRate = .fast
        store.synchronizePollingPreferences()
        await Task.yield()
        XCTAssertEqual(store.pollingState, .running)
        XCTAssertTrue(store.cpuHistory.isEmpty)
        XCTAssertTrue(store.volumes.isEmpty)
        XCTAssertEqual(gate.calls, 0)
    }

    @MainActor
    private func makeStore(preferences: Preferences, gate: ProcessSamplingGate) -> MonitorStore {
        MonitorStore(
            preferences: preferences,
            automaticallySchedulesPolling: false, processSampler: { reset in gate.sample(reset: reset) })
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(predicate(), "Synthetic process worker did not settle")
    }
}

private final class ProcessWeakStoreReference {
    weak var value: MonitorStore?
    init(_ value: MonitorStore?) { self.value = value }
}

/// The condition protects every mutable field; no production filesystem/process
/// query occurs and the synthetic group never resolves an icon or bundle path.
private final class ProcessSamplingGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var resetValues: [Bool] = []
    private var finishedCount = 0

    var calls: Int {
        condition.lock()
        defer { condition.unlock() }
        return resetValues.count
    }
    var resets: [Bool] {
        condition.lock()
        defer { condition.unlock() }
        return resetValues
    }
    var finishes: Int {
        condition.lock()
        defer { condition.unlock() }
        return finishedCount
    }

    func sample(reset: Bool) -> [ProcessGroup] {
        condition.lock()
        resetValues.append(reset)
        while !released { condition.wait() }
        finishedCount += 1
        condition.unlock()
        return [ProcessGroup(id: "synthetic-group", name: "Fixture", iconKey: nil, isSystemGroup: false, processes: [])]
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
