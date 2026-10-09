import IOKit.ps
import XCTest

@testable import SystemPulse

final class PowerDiagnosticsTests: XCTestCase {
    func testZeroChargeCanBeKnownWhileMissingCapacityIsUnavailable() {
        var power = PowerInfo()
        let source: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 0,
            kIOPSMaxCapacityKey: 100,
        ]
        PowerSampler.applyPowerSource(source, to: &power)
        XCTAssertTrue(power.hasChargeReading)
        XCTAssertEqual(power.chargePercent, 0)
        PowerSampler.applyPowerSource([kIOPSTypeKey: kIOPSInternalBatteryType], to: &power)
        XCTAssertFalse(power.hasChargeReading)
    }

    func testMissingAndZeroCycleCountAreDifferentStates() {
        var power = PowerInfo()
        PowerSampler.applyBatteryProperties([:], to: &power)
        XCTAssertFalse(power.hasCycleCountReading)
        PowerSampler.applyBatteryProperties(["CycleCount": 0], to: &power)
        XCTAssertTrue(power.hasCycleCountReading)
        XCTAssertEqual(power.cycleCount, 0)
        PowerSampler.applyBatteryProperties(["CycleCount": -1], to: &power)
        XCTAssertFalse(power.hasCycleCountReading)
    }

    func testChargingExplanationsDescribeObservedStateNotAnInventedLimit() {
        var power = PowerInfo(hasBattery: true, hasChargeReading: true, isPluggedIn: true)
        XCTAssertTrue(power.chargingExplanation.contains("exact reason and charge limit are not exposed"))
        XCTAssertFalse(power.chargingExplanation.contains("80%"))
        power.isCharging = true
        XCTAssertTrue(power.chargingExplanation.contains("macOS is charging"))
        power.isCharging = false
        power.isFullyCharged = true
        XCTAssertTrue(power.chargingExplanation.contains("fully charged"))
        power.isPluggedIn = false
        power.isFullyCharged = false
        XCTAssertTrue(power.chargingExplanation.contains("macOS estimate"))
    }

    func testMissingBatteryStateDoesNotClaimDischarging() {
        let power = PowerInfo(hasBattery: true)
        XCTAssertEqual(power.stateLabel, "Battery state unavailable")
        XCTAssertTrue(power.chargingExplanation.contains("unavailable"))
    }

    func testLowPowerModeUnknownIsDistinctFromDisabled() {
        var power = PowerInfo()
        XCTAssertNil(power.lowPowerModeEnabled)
        power.lowPowerModeEnabled = false
        XCTAssertEqual(power.lowPowerModeEnabled, false)
    }
}
