import Darwin
import XCTest

@testable import SystemPulse

final class LiveTelemetrySmokeTests: XCTestCase {
    /// Read-only integration test; never scans folders, sends signals, or changes preferences.
    func testLivePublicCountersAndProcessEnumeration() throws {
        guard ProcessInfo.processInfo.environment["SYSTEMPULSE_LIVE_SMOKE"] == "1" else {
            throw XCTSkip("Set SYSTEMPULSE_LIVE_SMOKE=1 to check the current Mac's read-only telemetry")
        }
        let sampler = SystemSampler()
        _ = sampler.cpuSample()
        Thread.sleep(forTimeInterval: 0.1)
        let cpu = sampler.cpuSample()
        XCTAssertFalse(cpu.perCore.isEmpty)
        XCTAssertTrue(cpu.perCore.allSatisfy { $0.isFinite && (0...100).contains($0) })
        XCTAssertTrue((0...100).contains(cpu.overall))
        let memory = sampler.memoryBreakdown()
        XCTAssertGreaterThan(memory.total, 0)
        XCTAssertGreaterThan(memory.used, 0)
        XCTAssertLessThanOrEqual(memory.used, memory.total)
        let disk = sampler.diskUsage()
        XCTAssertGreaterThan(disk.total, 0)
        XCTAssertLessThanOrEqual(disk.used, disk.total)
        XCTAssertLessThanOrEqual(disk.free, disk.total)
        let network = sampler.networkSnapshot()
        XCTAssertNotNil(network.interfaceCounters)
        let interfaces = try XCTUnwrap(network.interfaces)
        XCTAssertEqual(Set(interfaces.map(\.id)).count, interfaces.count)
        let volumes = VolumeSampler.sample()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertEqual(Set(volumes.map(\.id)).count, volumes.count)
        XCTAssertNotNil(VolumeSelection.resolve(selectedID: nil, in: volumes))
        for volume in volumes {
            if let used = volume.usedBytes, let total = volume.totalBytes { XCTAssertLessThanOrEqual(used, total) }
        }
        let groups = sampler.groupedProcesses()
        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(SystemSampler.processIDs().contains(getpid()))
        // The presentation sampler intentionally excludes SystemPulse itself.
        XCTAssertFalse(groups.flatMap(\.processes).contains { $0.id == getpid() })
        XCTAssertTrue(groups.flatMap(\.processes).allSatisfy { $0.cpu.isFinite && $0.cpu >= 0 })
        let info = sampler.systemInfo()
        XCTAssertGreaterThan(info.uptime, 0)
        XCTAssertGreaterThan(info.processCount, 0)
        let power = PowerSampler.sample()
        XCTAssertTrue(power.chargePercent.isFinite)
        XCTAssertNotNil(power.lowPowerModeEnabled)
        if power.hasBattery, power.hasChargeReading { XCTAssertTrue((0...100).contains(power.chargePercent)) }
        if let watts = power.systemPowerWatts { XCTAssertTrue(watts.isFinite && watts >= 0) }
    }
}
