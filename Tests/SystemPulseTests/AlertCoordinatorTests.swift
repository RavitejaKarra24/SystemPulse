import XCTest

@testable import SystemPulse

final class AlertCoordinatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testRepeatingCachedObservationDoesNotInventSustainedTime() {
        var coordinator = AlertCoordinator()
        var events: [AlertEvent] = []
        let reading = SampledAlertValue(value: 95, sampledAt: base)
        for second in 0...45 {
            events += coordinator.evaluate(
                [.cpuUsage: reading], at: base.addingTimeInterval(Double(second)),
                rules: [AlertRule(kind: .cpuUsage)], enabled: true)
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testSlowRealObservationsCanCompleteTheWindowWithoutRedatingCache() {
        var coordinator = AlertCoordinator()
        var events: [AlertEvent] = []
        for second in 0...40 {
            let observedAt = base.addingTimeInterval(Double(second / 6 * 6))
            events += coordinator.evaluate(
                [.diskAvailable: SampledAlertValue(value: 1_073_741_824, sampledAt: observedAt)],
                at: base.addingTimeInterval(Double(second)), rules: [AlertRule(kind: .diskAvailable)], enabled: true)
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(30))
        XCTAssertEqual(events.first?.duration, 30)
    }

    func testNewlyEnabledRuleWaitsForFreshPostEnableEvidence() {
        var coordinator = AlertCoordinator()
        var events: [AlertEvent] = []
        for second in 0...65 {
            let observedAt = base.addingTimeInterval(Double(second / 6 * 6))
            events += coordinator.evaluate(
                [.batteryCharge: SampledAlertValue(value: 10, sampledAt: observedAt)],
                at: base.addingTimeInterval(Double(second)),
                rules: [AlertRule(kind: .batteryCharge, enabled: second >= 20)], enabled: true)
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(54))
    }

    func testRuleEditRestartsFromNewActualEvidence() {
        var coordinator = AlertCoordinator()
        var events: [AlertEvent] = []
        for second in 0...72 {
            let observedAt = base.addingTimeInterval(Double(second / 6 * 6))
            events += coordinator.evaluate(
                [.batteryCharge: SampledAlertValue(value: 10, sampledAt: observedAt)],
                at: base.addingTimeInterval(Double(second)),
                rules: [AlertRule(kind: .batteryCharge, threshold: second < 25 ? 20 : 25)], enabled: true)
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(60))
    }

    func testNonfiniteFrameRecoversWithANewSustainedWindow() {
        var coordinator = AlertCoordinator()
        let rule = AlertRule(kind: .cpuUsage)
        _ = coordinator.evaluate(
            [.cpuUsage: SampledAlertValue(value: 95, sampledAt: base)], at: base, rules: [rule], enabled: true)
        XCTAssertTrue(
            coordinator.evaluate([:], at: Date(timeIntervalSince1970: .nan), rules: [rule], enabled: true).isEmpty)
        var events: [AlertEvent] = []
        for second in stride(from: 3, through: 33, by: 3) {
            let date = base.addingTimeInterval(Double(second))
            events += coordinator.evaluate(
                [.cpuUsage: SampledAlertValue(value: 95, sampledAt: date)], at: date, rules: [rule], enabled: true)
        }
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(33))
    }

    func testPreOptInObservationDoesNotShortenWarmup() {
        var coordinator = AlertCoordinator()
        let rule = AlertRule(kind: .batteryCharge)
        for second in 0...20 {
            let events = coordinator.evaluate(
                [.batteryCharge: SampledAlertValue(value: 10, sampledAt: base.addingTimeInterval(-5))],
                at: base.addingTimeInterval(Double(second)), rules: [rule], enabled: true)
            XCTAssertTrue(events.isEmpty)
        }
        var events: [AlertEvent] = []
        for second in stride(from: 21, through: 51, by: 3) {
            let time = base.addingTimeInterval(Double(second))
            events += coordinator.evaluate(
                [.batteryCharge: SampledAlertValue(value: 10, sampledAt: time)], at: time, rules: [rule], enabled: true)
        }
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(51))
    }
}
