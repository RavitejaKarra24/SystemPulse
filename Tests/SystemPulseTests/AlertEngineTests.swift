import XCTest

@testable import SystemPulse

final class AlertEngineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let cpu = AlertRule(kind: .cpuUsage)

    private func evaluate(
        _ engine: inout AlertEngine, _ second: Double, value: Double? = 90,
        rules: [AlertRule]? = nil, enabled: Bool = true
    ) -> [AlertEvent] {
        engine.evaluate(
            value.map { [.cpuUsage: $0] } ?? [:], at: base.addingTimeInterval(second),
            rules: rules ?? [cpu], enabled: enabled)
    }

    private func sustain(_ engine: inout AlertEngine, from start: Int, through end: Int) -> [AlertEvent] {
        stride(from: start, through: end, by: 5).flatMap { evaluate(&engine, Double($0)) }
    }

    func testWarmupAndExactInclusiveThreshold() throws {
        var engine = AlertEngine()
        XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
        let event = try XCTUnwrap(evaluate(&engine, 30).first)
        XCTAssertEqual(event.kind, .cpuUsage)
        XCTAssertEqual(event.timestamp, base.addingTimeInterval(30))
        XCTAssertEqual(event.value, 90)
        XCTAssertEqual(event.threshold, 90)
        XCTAssertEqual(event.duration, 30)
        XCTAssertEqual(event.title, AlertKind.cpuUsage.title)
        XCTAssertFalse(event.message.isEmpty)
    }

    func testRecoveryRestartsPendingWindow() {
        var engine = AlertEngine()
        XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
        XCTAssertTrue(evaluate(&engine, 30, value: 89).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 35, through: 60).isEmpty)
        XCTAssertEqual(evaluate(&engine, 65).count, 1)
    }

    func testNoPeriodicSpamAndRecoveryRearmsOnlyAfterCooldown() {
        var engine = AlertEngine()
        XCTAssertEqual(sustain(&engine, from: 0, through: 30).count, 1)
        XCTAssertTrue(sustain(&engine, from: 35, through: 1000).isEmpty)
        XCTAssertTrue(evaluate(&engine, 1005, value: 0).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 1010, through: 1035).isEmpty)
        XCTAssertEqual(evaluate(&engine, 1040).count, 1)
        XCTAssertTrue(sustain(&engine, from: 1045, through: 2000).isEmpty)
    }

    func testRecoveredBreachWaitsForCooldownWhileContinuouslySustained() {
        var engine = AlertEngine()
        XCTAssertEqual(sustain(&engine, from: 0, through: 30).count, 1)
        XCTAssertTrue(evaluate(&engine, 35, value: 0).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 40, through: 925).isEmpty)
        XCTAssertEqual(evaluate(&engine, 930).count, 1)
    }

    func testMissingAndInvalidSamplesResetPending() {
        let invalidValues: [Double?] = [nil, .nan, .infinity, -.infinity, -1, 101]
        for value in invalidValues {
            var engine = AlertEngine()
            XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
            XCTAssertTrue(evaluate(&engine, 30, value: value).isEmpty)
            XCTAssertTrue(sustain(&engine, from: 35, through: 60).isEmpty)
            XCTAssertEqual(evaluate(&engine, 65).count, 1)
        }
    }

    func testUnavailableDataIsNotRecoveryAndDoesNotUnlatch() {
        var engine = AlertEngine()
        XCTAssertEqual(sustain(&engine, from: 0, through: 30).count, 1)
        XCTAssertTrue(evaluate(&engine, 35, value: nil).isEmpty)
        XCTAssertTrue(evaluate(&engine, 40, value: .nan).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 2000, through: 2040).isEmpty)
        XCTAssertTrue(evaluate(&engine, 2045, value: 0).isEmpty)
        XCTAssertEqual(sustain(&engine, from: 2050, through: 2080).count, 1)
    }

    func testSleepGapRestartsWarmupButTenSecondGapsAreAllowed() {
        var engine = AlertEngine()
        XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
        XCTAssertTrue(evaluate(&engine, 36).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 41, through: 61).isEmpty)
        XCTAssertEqual(evaluate(&engine, 66).count, 1)
        var tenSecondEngine = AlertEngine()
        for second in [0.0, 10, 20] { XCTAssertTrue(evaluate(&tenSecondEngine, second).isEmpty) }
        XCTAssertEqual(evaluate(&tenSecondEngine, 30).count, 1)
        XCTAssertEqual(AlertEngine.maximumContinuityGap, 10)
    }

    func testDuplicateAndBackwardsTimestampsDiscardSampleAndResetPending() {
        for invalidTime in [25.0, 20.0] {
            var engine = AlertEngine()
            XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
            XCTAssertTrue(evaluate(&engine, invalidTime).isEmpty)
            XCTAssertTrue(sustain(&engine, from: 30, through: 55).isEmpty)
            XCTAssertEqual(evaluate(&engine, 60).count, 1)
        }
    }

    func testInvalidDateResetsPendingWithoutUnlatching() {
        var engine = AlertEngine()
        XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
        XCTAssertTrue(
            engine.evaluate(
                [.cpuUsage: 90], at: Date(timeIntervalSinceReferenceDate: .nan), rules: [cpu], enabled: true
            )
            .isEmpty)
        XCTAssertTrue(sustain(&engine, from: 30, through: 55).isEmpty)
        XCTAssertEqual(evaluate(&engine, 60).count, 1)
        XCTAssertTrue(evaluate(&engine, 59).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 2000, through: 2040).isEmpty)
    }

    func testGlobalDisableClearsPendingLatchAndCooldown() {
        var engine = AlertEngine()
        XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
        XCTAssertTrue(evaluate(&engine, 30, enabled: false).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 35, through: 60).isEmpty)
        XCTAssertEqual(evaluate(&engine, 65).count, 1)
        XCTAssertTrue(evaluate(&engine, 70, enabled: false).isEmpty)
        XCTAssertTrue(sustain(&engine, from: 75, through: 100).isEmpty)
        XCTAssertEqual(evaluate(&engine, 105).count, 1)
    }

    func testPerRuleDisableAndRemovalRequireNewWindow() {
        var off = cpu
        off.enabled = false
        for rules in [[off], []] {
            var engine = AlertEngine()
            XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
            XCTAssertTrue(evaluate(&engine, 30, rules: rules).isEmpty)
            XCTAssertTrue(sustain(&engine, from: 35, through: 60).isEmpty)
            XCTAssertEqual(evaluate(&engine, 65).count, 1)
        }
    }

    func testRuleEditsRestartWindow() {
        for edited in [
            AlertRule(kind: .cpuUsage, threshold: 85),
            AlertRule(kind: .cpuUsage, duration: 35),
            AlertRule(kind: .cpuUsage, cooldown: 1000),
        ] {
            var engine = AlertEngine()
            XCTAssertTrue(sustain(&engine, from: 0, through: 25).isEmpty)
            for second in stride(from: 30.0, through: 55, by: 5) {
                XCTAssertTrue(evaluate(&engine, second, rules: [edited]).isEmpty)
            }
            let events = evaluate(&engine, 30 + edited.duration, rules: [edited])
            XCTAssertEqual(events.count, 1)
        }
    }

    func testAllKindsUseCorrectDirectionAndMissingBatteryNeverAlerts() {
        let measurements: [AlertKind: Double] = [
            .cpuUsage: 90, .memoryHeadroom: 10, .diskAvailable: 5 * 1_073_741_824, .thermal: 2,
        ]
        var engine = AlertEngine()
        for second in stride(from: 0.0, through: 25, by: 5) {
            XCTAssertTrue(
                engine.evaluate(
                    measurements, at: base.addingTimeInterval(second), rules: AlertRule.defaults, enabled: true
                )
                .isEmpty)
        }
        let events = engine.evaluate(
            measurements, at: base.addingTimeInterval(30), rules: AlertRule.defaults, enabled: true)
        XCTAssertEqual(events.map(\.kind), [.cpuUsage, .memoryHeadroom, .diskAvailable, .thermal])
        XCTAssertTrue(events.first { $0.kind == .memoryHeadroom }?.message.contains("ESTIMATED") ?? false)
        XCTAssertTrue(events.first { $0.kind == .memoryHeadroom }?.message.contains("not OS memory pressure") ?? false)
        var batteryEngine = AlertEngine()
        let eventsOnBattery = stride(from: 0.0, through: 30, by: 5).flatMap { second in
            batteryEngine.evaluate(
                [.batteryCharge: 20], at: base.addingTimeInterval(second), rules: AlertRule.defaults, enabled: true)
        }
        XCTAssertEqual(eventsOnBattery.map(\.kind), [.batteryCharge])
    }

    func testHealthyLowThresholdMetricsAndInvalidThermalNeverAlert() {
        for thermal in [0.0, 1, 1.5, 4, .nan] {
            var engine = AlertEngine()
            for second in stride(from: 0.0, through: 60, by: 5) {
                XCTAssertTrue(
                    engine.evaluate(
                        [
                            .memoryHeadroom: 11, .diskAvailable: 6 * 1_073_741_824, .batteryCharge: 21,
                            .thermal: thermal,
                        ],
                        at: base.addingTimeInterval(second), rules: AlertRule.defaults, enabled: true
                    ).isEmpty)
            }
        }
    }

    func testCorruptRulesCannotBypassWarmupAndCooldown() {
        for duration in [0.0, -1, .nan, .infinity] {
            var corrupt = cpu
            corrupt.duration = duration
            corrupt.cooldown = -100
            corrupt.threshold = .nan
            var engine = AlertEngine()
            for second in stride(from: 0.0, through: 25, by: 5) {
                XCTAssertTrue(evaluate(&engine, second, rules: [corrupt]).isEmpty)
            }
            XCTAssertEqual(evaluate(&engine, 30, rules: [corrupt]).count, 1)
            XCTAssertTrue(evaluate(&engine, 35, value: 0, rules: [corrupt]).isEmpty)
            for second in stride(from: 40.0, through: 925, by: 5) {
                XCTAssertTrue(evaluate(&engine, second, rules: [corrupt]).isEmpty)
            }
            XCTAssertEqual(evaluate(&engine, 930, rules: [corrupt]).count, 1)
        }
    }

    func testNormalizationBoundsDefaultsAndDeduplication() {
        XCTAssertEqual(AlertRule.defaults.count, 5)
        XCTAssertTrue(AlertRule.defaults.allSatisfy { $0.enabled && $0.duration >= 30 && $0.cooldown >= 900 })
        XCTAssertEqual(AlertRule(kind: .diskAvailable).threshold, 5 * 1_073_741_824)
        XCTAssertEqual(AlertRule(kind: .thermal, threshold: 1).threshold, 2)
        XCTAssertEqual(AlertRule(kind: .thermal, threshold: 2.1).threshold, 3)
        let bounded = AlertRule(kind: .cpuUsage, threshold: -1, duration: .greatestFiniteMagnitude, cooldown: 1e100)
        XCTAssertEqual(bounded.threshold, 90)
        XCTAssertEqual(bounded.duration, 86_400)
        XCTAssertEqual(bounded.cooldown, 604_800)
        let rules = AlertRule.normalized([
            AlertRule(kind: .thermal), AlertRule(kind: .cpuUsage, enabled: false), cpu,
        ])
        XCTAssertEqual(rules.map(\.kind), [.cpuUsage, .thermal])
        XCTAssertFalse(rules[0].enabled)
        var engine = AlertEngine()
        let duplicates = [cpu, cpu]
        let events = stride(from: 0.0, through: 30, by: 5).flatMap { evaluate(&engine, $0, rules: duplicates) }
        XCTAssertEqual(events.count, 1)
    }

    func testCodableNormalizesCorruptAndMissingValuesAndEventRoundTrips() throws {
        let json = Data(#"{"kind":"cpuUsage","enabled":"bad","threshold":999,"duration":0,"cooldown":-2}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AlertRule.self, from: json), cpu)
        XCTAssertEqual(try JSONDecoder().decode(AlertRule.self, from: Data(#"{"kind":"cpuUsage"}"#.utf8)), cpu)
        XCTAssertThrowsError(try JSONDecoder().decode(AlertRule.self, from: Data(#"{"kind":"unknown"}"#.utf8)))
        let event = AlertEvent(kind: .memoryHeadroom, timestamp: base, value: 5, threshold: 10, duration: 30)
        let decoded = try JSONDecoder().decode(AlertEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.message, event.message)
        for kind in AlertKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.unitLabel.isEmpty)
            XCTAssertEqual(kind.id, kind)
        }
    }
}
