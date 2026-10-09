import XCTest

@testable import SystemPulse

final class PhaseThreeStoreTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func preferences() throws -> (Preferences, UserDefaults, String) {
        let name = "SystemPulse.PhaseThree.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (Preferences(defaults: defaults), defaults, name)
    }

    @MainActor
    private func sample(
        _ store: MonitorStore, at timestamp: Date, cpu: Double = 95, disk: Bool = false, power: PowerInfo? = nil,
        evaluatedAt: Date? = nil
    ) {
        store.applySample(
            cpu: .init(perCore: [cpu, cpu]),
            memory: MemoryBreakdown(app: 500, wired: 200, compressed: 100, cached: 100, free: 100, total: 1000),
            io: DiskIOSnapshot(timestamp: timestamp), power: power,
            net: NetworkSnapshot(timestamp: timestamp),
            disk: disk ? .init(total: 500 << 30, used: 290 << 30, free: 210 << 30) : nil,
            info: nil, thermal: .nominal, evaluatedAt: evaluatedAt ?? timestamp)
    }

    @MainActor
    func testAlertsRequireBothOptInAndPermissionAndNeverFireImmediately() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.alertRules = [AlertRule(kind: .cpuUsage, enabled: true, threshold: 90, duration: 30, cooldown: 900)]
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: prefs, alertSink: { events.append($0) })
        for tick in 0...12 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        XCTAssertTrue(events.isEmpty, "Global opt-in is off")
        prefs.alertsEnabled = true
        for tick in 13...25 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        XCTAssertTrue(events.isEmpty, "Permission has not been granted")
        store.notificationDeliveryAllowed = true
        sample(store, at: base.addingTimeInterval(78))
        XCTAssertTrue(events.isEmpty, "Authorization does not produce a startup alert")
        for tick in 27...40 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .cpuUsage)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(events.first?.timestamp), base.addingTimeInterval(108))
    }

    @MainActor
    func testBriefGlobalOptOutBetweenSamplesRestartsWarmup() async throws {
        try await assertWarmupRestarts { preferences, _ in
            preferences.alertsEnabled = false
            preferences.alertsEnabled = true
        }
    }

    @MainActor
    func testRuleEditAndRevertBetweenSamplesRestartsOnlyThatRule() async throws {
        try await assertWarmupRestarts { preferences, _ in
            let original = preferences.alertRules
            var edited = original
            edited[0].threshold = 99
            preferences.alertRules = edited
            preferences.alertRules = original
        }
    }

    @MainActor
    func testBriefPermissionRevocationBetweenSamplesRestartsWarmup() async throws {
        try await assertWarmupRestarts { _, store in
            store.notificationDeliveryAllowed = false
            store.notificationDeliveryAllowed = true
        }
    }

    @MainActor
    func testUnrelatedRuleEditDoesNotRestartCPUWarmup() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.alertsEnabled = true
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: prefs, alertSink: { events.append($0) })
        store.notificationDeliveryAllowed = true
        for tick in 0...9 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        var rules = prefs.alertRules
        let diskIndex = try XCTUnwrap(rules.firstIndex { $0.kind == .diskAvailable })
        rules[diskIndex].threshold = Double(1 << 30)
        prefs.alertRules = rules
        sample(store, at: base.addingTimeInterval(30))
        XCTAssertEqual(events.map(\.kind), [.cpuUsage])
    }

    @MainActor
    private func assertWarmupRestarts(_ change: (Preferences, MonitorStore) -> Void) async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.alertsEnabled = true
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: prefs, alertSink: { events.append($0) })
        store.notificationDeliveryAllowed = true
        for tick in 0...9 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        XCTAssertTrue(events.isEmpty)
        change(prefs, store)
        for tick in 10...19 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        XCTAssertTrue(events.isEmpty, "A transient opt-out/edit must invalidate previously sustained evidence")
        sample(store, at: base.addingTimeInterval(60))
        XCTAssertEqual(events.map(\.kind), [.cpuUsage])
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(60))
    }

    @MainActor
    func testDelayedPassDoesNotWarnOnWakeAndRequiresNewEvidence() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.alertsEnabled = true
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: prefs, alertSink: { events.append($0) })
        store.notificationDeliveryAllowed = true
        for tick in 0...9 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        sample(store, at: base.addingTimeInterval(30), evaluatedAt: base.addingTimeInterval(300))
        XCTAssertTrue(events.isEmpty, "A stale pass applied after sleep/I/O cannot complete warmup")
        for tick in 101...110 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        XCTAssertTrue(events.isEmpty)
        sample(store, at: base.addingTimeInterval(333))
        XCTAssertEqual(events.map(\.kind), [.cpuUsage])
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(333))
    }

    @MainActor
    func testDifferentSourcesKeepTheirActualAcquisitionTimes() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MonitorStore(startPolling: false, preferences: prefs)
        let end = base.addingTimeInterval(20)
        store.applySample(
            cpu: .init(perCore: [95]),
            memory: MemoryBreakdown(app: 500, wired: 200, compressed: 100, cached: 100, free: 100, total: 1000),
            io: DiskIOSnapshot(timestamp: end), power: nil, net: NetworkSnapshot(timestamp: end),
            disk: .init(total: 1000, used: 800, free: 200), info: nil, thermal: .serious,
            observationTimes: SampleObservationTimes(cpu: base, memory: end, power: nil, disk: end, thermal: end),
            evaluatedAt: end)
        XCTAssertNil(store.menuBarReadings(at: end).cpuPercent)
        XCTAssertEqual(store.menuBarReadings(at: end).memoryPercent, 80)
        XCTAssertEqual(store.sampledAlertMeasurements(at: end)[.diskAvailable]?.sampledAt, end)
        XCTAssertEqual(store.cpuTimeline.latestTimestamp, base)
        XCTAssertEqual(store.memoryTimeline.latestTimestamp, end)
    }

    @MainActor
    func testCachedPowerCannotBridgeMissingRealObservations() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.alertsEnabled = true
        prefs.alertRules = AlertKind.allCases.map { AlertRule(kind: $0, enabled: $0 == .batteryCharge) }
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: prefs, alertSink: { events.append($0) })
        store.notificationDeliveryAllowed = true
        for tick in 0...20 {
            let power = tick % 5 == 0 ? PowerInfo(hasBattery: true, chargePercent: 10, hasChargeReading: true) : nil
            sample(store, at: base.addingTimeInterval(Double(tick) * 3), cpu: 10, power: power)
        }
        XCTAssertTrue(events.isEmpty, "15-second gaps between real power observations break the sustained window")
    }

    @MainActor
    func testFreshnessAndHomeCapacityAreIndependentOfSelectedVolume() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MonitorStore(startPolling: false, preferences: prefs)
        sample(
            store, at: base, disk: true, power: PowerInfo(hasBattery: true, chargePercent: 15, hasChargeReading: true))
        store.applyVolumes([
            MonitoredVolume(
                id: "external", name: "Fixture", mountURL: URL(fileURLWithPath: "/Volumes/Fixture"),
                isInternal: false, isReadOnly: false, totalBytes: 20 << 30, availableBytes: 2 << 30)
        ])
        store.selectedVolumeID = "external"
        let readings = store.menuBarReadings(at: base)
        XCTAssertEqual(readings.diskAvailableBytes, 210 << 30)
        XCTAssertEqual(readings.cpuPercent, 95)
        XCTAssertEqual(store.alertMeasurements(at: base)[.memoryHeadroom], 20)
        XCTAssertEqual(store.alertMeasurements(at: base)[.batteryCharge], 15)
        XCTAssertTrue(store.alertMeasurements(at: base.addingTimeInterval(30)).isEmpty)
        XCTAssertNil(store.menuBarReadings(at: base.addingTimeInterval(-1)).cpuPercent)
    }

    @MainActor
    func testACAndUnknownBatteryDoNotTriggerLowChargeMeasurements() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MonitorStore(startPolling: false, preferences: prefs)
        sample(
            store, at: base,
            power: PowerInfo(hasBattery: true, chargePercent: 0, hasChargeReading: true, isPluggedIn: true))
        XCTAssertNil(store.alertMeasurements(at: base)[.batteryCharge])
        sample(store, at: base.addingTimeInterval(3), power: PowerInfo(hasBattery: true))
        XCTAssertNil(store.alertMeasurements(at: base.addingTimeInterval(3))[.batteryCharge])
        XCTAssertNil(store.menuBarReadings(at: base.addingTimeInterval(3)).batteryChargePercent)
    }

    @MainActor
    func testSustainedInsightsUseMeasuredCPUAndRecentProcessPass() async throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MonitorStore(startPolling: false, preferences: prefs)
        for tick in 0...15 { sample(store, at: base.addingTimeInterval(Double(tick) * 3)) }
        let end = base.addingTimeInterval(45)
        let insights = store.monitoringInsights(at: end)
        XCTAssertTrue(insights.contains { $0.metric == .cpu })
        XCTAssertTrue(store.monitoringInsights(at: end.addingTimeInterval(60)).isEmpty)
        XCTAssertFalse(prefs.alertsEnabled)
    }
}
