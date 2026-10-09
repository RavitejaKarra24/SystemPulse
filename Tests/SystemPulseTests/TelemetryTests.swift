import Darwin
import Foundation
import IOKit.ps
import XCTest

@testable import SystemPulse

final class TelemetryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 100)

    func testCounterFirstSampleIsBaselineAndRatesUseElapsedTime() {
        var tracker = CounterRateTracker()
        tracker.apply(["en0": ByteCounters(first: 100, second: 200)], at: epoch)
        XCTAssertEqual(tracker.firstRate, 0)
        XCTAssertEqual(tracker.firstTotal, 0)
        tracker.apply(["en0": ByteCounters(first: 160, second: 300)], at: epoch.addingTimeInterval(2))
        XCTAssertEqual(tracker.firstRate, 30)
        XCTAssertEqual(tracker.secondRate, 50)
        XCTAssertEqual(tracker.firstTotal, 60)
        XCTAssertEqual(tracker.secondTotal, 100)
    }

    func testCounterResetHasNoUnsignedSpikeAndRecovers() {
        var tracker = CounterRateTracker()
        tracker.apply(["disk": ByteCounters(first: 100, second: 100)], at: epoch)
        tracker.apply(["disk": ByteCounters(first: 10, second: 150)], at: epoch.addingTimeInterval(1))
        XCTAssertEqual(tracker.firstRate, 0)
        XCTAssertEqual(tracker.secondRate, 50)
        tracker.apply(["disk": ByteCounters(first: 30, second: 170)], at: epoch.addingTimeInterval(2))
        XCTAssertEqual(tracker.firstRate, 20)
        XCTAssertEqual(tracker.firstTotal, 20)
        XCTAssertEqual(tracker.secondTotal, 70)
    }

    func testInvalidTimestampsClearRatesWithoutConsumingBaselineOrBytes() {
        var tracker = CounterRateTracker()
        tracker.apply(["a": ByteCounters(first: 0, second: 0)], at: epoch)
        tracker.apply(["a": ByteCounters(first: 10, second: 20)], at: epoch.addingTimeInterval(1))
        for time in [epoch, epoch.addingTimeInterval(1)] {
            tracker.apply(["a": ByteCounters(first: 100, second: 200)], at: time)
            XCTAssertEqual(tracker.firstRate, 0)
            XCTAssertEqual(tracker.secondRate, 0)
            XCTAssertEqual(tracker.firstTotal, 10)
        }
        tracker.apply(["a": ByteCounters(first: 30, second: 50)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.firstRate, 10)
        XCTAssertEqual(tracker.firstTotal, 30)
        XCTAssertEqual(tracker.secondTotal, 50)
    }

    func testInterfaceRemovalAdditionAndResetDoNotEraseOtherTraffic() {
        var tracker = CounterRateTracker()
        tracker.apply(
            ["en0": ByteCounters(first: 100, second: 0), "en1": ByteCounters(first: 1000, second: 0)], at: epoch)
        tracker.apply(
            ["en0": ByteCounters(first: 150, second: 0), "en2": ByteCounters(first: 9000, second: 0)],
            at: epoch.addingTimeInterval(1))
        XCTAssertEqual(tracker.firstRate, 50)
        tracker.apply(
            ["en0": ByteCounters(first: 175, second: 0), "en2": ByteCounters(first: 10, second: 0)],
            at: epoch.addingTimeInterval(2))
        XCTAssertEqual(tracker.firstRate, 25)
        XCTAssertEqual(tracker.firstTotal, 75)
    }

    func testSessionCounterSaturatesRatherThanTrappingOnOverflow() {
        var tracker = CounterRateTracker()
        tracker.apply(["a": ByteCounters(first: 0, second: 0)], at: epoch)
        tracker.apply(["a": ByteCounters(first: .max, second: .max)], at: epoch.addingTimeInterval(1))
        tracker.apply(["a": ByteCounters(first: 0, second: 0)], at: epoch.addingTimeInterval(2))
        tracker.apply(["a": ByteCounters(first: 1, second: 1)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.firstTotal, .max)
        XCTAssertEqual(tracker.secondTotal, .max)
    }

    func testCPURequiresBaselineAndNoTicksMeansZero() {
        let ticks: [Int32] = [100, 100, 800, 0]
        XCTAssertEqual(SystemSampler.cpuUsage(current: ticks, previous: nil), 0)
        XCTAssertEqual(SystemSampler.cpuUsage(current: ticks, previous: ticks), 0)
        XCTAssertEqual(SystemSampler.cpuUsage(current: ticks, previous: [0]), 0)
    }

    func testCPUUnsignedSignBitAndWraparound() {
        var prior = [Int32](repeating: 0, count: Int(CPU_STATE_MAX))
        var current = prior
        prior[Int(CPU_STATE_USER)] = Int32.max - 9
        current[Int(CPU_STATE_USER)] = Int32(bitPattern: UInt32(Int32.max) + 11)
        current[Int(CPU_STATE_IDLE)] = 20
        XCTAssertEqual(SystemSampler.cpuUsage(current: current, previous: prior), 50)
        prior[Int(CPU_STATE_USER)] = Int32(bitPattern: UInt32.max - 9)
        current[Int(CPU_STATE_USER)] = 10
        XCTAssertEqual(SystemSampler.cpuUsage(current: current, previous: prior), 50)
    }

    func testProcessEnumerationTreatsReturnAsCountNotBytes() {
        let expected: [pid_t] = [2, 3, 4, 5, 6, 7, 8]
        let pids = SystemSampler.processIDs { pointer, bytes in
            guard let pointer else { return 20 }  // sizing includes padding
            XCTAssertGreaterThanOrEqual(Int(bytes), expected.count * MemoryLayout<pid_t>.stride)
            expected.withUnsafeBytes { source in
                pointer.copyMemory(from: source.baseAddress!, byteCount: source.count)
            }
            return Int32(expected.count)
        }
        XCTAssertEqual(pids, expected)
    }

    func testProcessEnumerationRetriesWhenBufferFills() {
        var fills = 0
        let pids = SystemSampler.processIDs { pointer, bytes in
            guard let pointer else { return 1 }
            fills += 1
            let capacity = Int(bytes) / MemoryLayout<pid_t>.stride
            let count = fills == 1 ? capacity : 18
            for i in 0..<count { pointer.assumingMemoryBound(to: pid_t.self)[i] = pid_t(i + 2) }
            return Int32(count)
        }
        XCTAssertEqual(fills, 2)
        XCTAssertEqual(pids.count, 18)
        XCTAssertEqual(pids.last, 19)
    }

    func testProcessEnumerationFailuresReturnEmpty() {
        XCTAssertTrue(SystemSampler.processIDs { _, _ in -1 }.isEmpty)
        XCTAssertTrue(SystemSampler.processIDs { pointer, _ in pointer == nil ? 20 : 0 }.isEmpty)
    }

    func testNetworkOnlyAcceptsPhysicalLinkLayerRecords() {
        XCTAssertTrue(SystemSampler.isPhysicalNetworkInterface("en0", family: UInt8(AF_LINK)))
        XCTAssertFalse(SystemSampler.isPhysicalNetworkInterface("en0", family: UInt8(AF_INET)))
        XCTAssertFalse(SystemSampler.isPhysicalNetworkInterface("en0", family: UInt8(AF_INET6)))
        for name in ["bridge0", "lo0", "utun0", "awdl0"] {
            XCTAssertFalse(SystemSampler.isPhysicalNetworkInterface(name, family: UInt8(AF_LINK)))
        }
        XCTAssertFalse(SystemSampler.isPhysicalNetworkInterface("en0", family: nil))
    }

    func testSwapUsesActualUsedBytesNotTotalOrPageouts() {
        let used = SystemSampler.swapUsed { usage, size in
            XCTAssertEqual(size, MemoryLayout<xsw_usage>.stride)
            usage.xsu_total = 8_000_000
            usage.xsu_avail = 6_000_000
            usage.xsu_used = 2_000_000
            return 0
        }
        let memory = MemoryBreakdown(
            app: 50, wired: 20, compressed: 10, cached: 10, free: 10, total: 100, swapUsed: used)
        XCTAssertEqual(memory.swapUsed, 2_000_000)
        XCTAssertEqual(memory.used, 80)  // swap is not physical memory
        XCTAssertEqual(memory.usedPercent, 80)
        XCTAssertNil(MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: 0).swapUsed)
    }

    func testSwapFailedAndTruncatedQueriesAreUnavailable() {
        XCTAssertNil(
            SystemSampler.swapUsed { usage, _ in
                usage.xsu_used = 123
                return -1
            })
        XCTAssertNil(
            SystemSampler.swapUsed { usage, size in
                usage.xsu_used = 123
                size -= 1
                return 0
            })
        XCTAssertEqual(
            SystemSampler.swapUsed { usage, _ in
                usage.xsu_used = 0
                return 0
            }, 0)
    }

    func testPowerChargeIsClampedAndOptimizedChargingHasNoTimeLeft() {
        var power = PowerInfo()
        let source: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 120,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSTimeToEmptyKey: 30,
        ]
        XCTAssertTrue(PowerSampler.applyPowerSource(source, to: &power))
        XCTAssertEqual(power.chargePercent, 100)
        XCTAssertNil(power.timeRemaining)
        XCTAssertEqual(power.timeRemainingFormatted, "Not charging")
        XCTAssertFalse(PowerSampler.applyPowerSource([kIOPSTypeKey: "UPS"], to: &power))
    }

    func testPowerChargingAndDischargingEstimatesUseSeconds() {
        var power = PowerInfo()
        var source: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsChargingKey: true,
            kIOPSTimeToFullChargeKey: 90,
        ]
        PowerSampler.applyPowerSource(source, to: &power)
        XCTAssertEqual(power.timeRemaining, 5400)
        XCTAssertEqual(power.timeRemainingFormatted, "1h 30m to full")
        source[kIOPSIsChargingKey] = false
        source[kIOPSTimeToEmptyKey] = 45
        PowerSampler.applyPowerSource(source, to: &power)
        XCTAssertEqual(power.timeRemaining, 2700)
        source[kIOPSTimeToEmptyKey] = -1
        PowerSampler.applyPowerSource(source, to: &power)
        XCTAssertNil(power.timeRemaining)
    }

    func testBatteryHealthDoesNotMixNormalizedPercentAndMAh() {
        var power = PowerInfo()
        PowerSampler.applyBatteryProperties(["DesignCapacity": 5000, "MaxCapacity": 100], to: &power)
        XCTAssertEqual(power.healthPercent, 0)
        XCTAssertEqual(power.fullChargeCapacity, 0)
        PowerSampler.applyBatteryProperties(
            ["DesignCapacity": 5000, "MaxCapacity": 100, "AppleRawMaxCapacity": 4000], to: &power)
        XCTAssertEqual(power.healthPercent, 80)
        XCTAssertEqual(power.fullChargeCapacity, 4000)
    }

    func testBatteryPowerPreservesDischargingSign() {
        var power = PowerInfo()
        PowerSampler.applyBatteryProperties(["Voltage": 12000, "Amperage": -2000], to: &power)
        XCTAssertEqual(power.batteryPowerWatts, -24)
        XCTAssertNil(power.systemPowerWatts)
    }

    func testInvalidPowerEstimatesDoNotTrapFormatting() {
        for estimate in [Double.nan, Double.infinity, -1, 0, Double(Int.max)] {
            var power = PowerInfo()
            power.timeRemaining = estimate
            XCTAssertEqual(power.timeRemainingFormatted, "Estimating…")
        }
    }
}
