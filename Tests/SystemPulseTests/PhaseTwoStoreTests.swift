import XCTest

@testable import SystemPulse

final class PhaseTwoStoreTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func network(_ bytes: UInt64, at timestamp: Date, present: Bool = true) -> NetworkSnapshot {
        let interface = NetworkInterfaceSnapshot(
            name: "en0", displayName: "Wi-Fi", addresses: ["192.0.2.1"], isActive: true,
            kind: .wifi, bytesIn: bytes, bytesOut: bytes / 2)
        return NetworkSnapshot(
            bytesIn: bytes, bytesOut: bytes / 2, timestamp: timestamp,
            interfaceCounters: present ? ["en0": ByteCounters(first: bytes, second: bytes / 2)] : [:],
            interfaces: present ? [interface] : [])
    }

    @MainActor
    func testNetworkTimelinesUseReadingTimestampsAndSelectedSeriesResetOnSwitch() async {
        let store = MonitorStore(startPolling: false)
        store.applyNetwork(network(100, at: base))
        store.selectedNetworkInterfaceID = "en0"
        store.applyNetwork(network(140, at: base.addingTimeInterval(2)))
        XCTAssertEqual(store.netInRate, 20)
        XCTAssertEqual(store.networkPageInRate, 20)
        XCTAssertEqual(store.selectedDownloadTimeline.latestTimestamp, base.addingTimeInterval(2))
        XCTAssertEqual(store.downloadTimeline.latestTimestamp, base.addingTimeInterval(2))
        store.selectedNetworkInterfaceID = nil
        XCTAssertNil(store.selectedDownloadTimeline.latestTimestamp)
        XCTAssertEqual(store.networkPageDownloadTimeline.latestTimestamp, base.addingTimeInterval(2))
        store.selectedNetworkInterfaceID = "en0"
        XCTAssertTrue(
            store.networkPageDownloadTimeline.points(in: .fiveMinutes, endingAt: base.addingTimeInterval(2)).isEmpty)
    }

    @MainActor
    func testDisconnectedInterfaceDoesNotInventHistorySamples() async {
        let store = MonitorStore(startPolling: false)
        store.selectedNetworkInterfaceID = "en0"
        store.applyNetwork(network(100, at: base))
        store.applyNetwork(network(140, at: base.addingTimeInterval(2)))
        store.applyNetwork(network(140, at: base.addingTimeInterval(4), present: false))
        XCTAssertEqual(store.selectedDownloadTimeline.latestTimestamp, base.addingTimeInterval(2))
        XCTAssertEqual(store.networkPageInRate, 0)
        XCTAssertFalse(store.selectedNetworkInterface?.isPresent ?? true)
    }

    @MainActor
    func testRemovedVolumeFallsBackAndUnavailableCapacityDoesNotExportHomeValues() async {
        let store = MonitorStore(startPolling: false)
        store.diskTotal = 500
        store.diskFree = 250
        let home = MonitoredVolume(
            id: "home", name: "Home", mountURL: URL(fileURLWithPath: "/System/Volumes/Data"),
            isInternal: true, isReadOnly: false, totalBytes: 500, availableBytes: 250, isHomeVolume: true)
        let external = MonitoredVolume(
            id: "usb", name: "Fixture drive", mountURL: URL(fileURLWithPath: "/Volumes/Fixture"),
            isInternal: false, isReadOnly: true, totalBytes: nil, availableBytes: nil)
        store.applyVolumes([home, external])
        store.selectedVolumeID = "usb"
        let snapshot = store.diagnosticSnapshot(capturedAt: base)
        XCTAssertNil(snapshot.volumeTotalBytes)
        XCTAssertNil(snapshot.volumeAvailableBytes)
        XCTAssertEqual(store.selectedVolume?.id, "usb")
        store.applyVolumes([home])
        XCTAssertNil(store.selectedVolumeID)
        XCTAssertEqual(store.selectedVolume?.id, "home")
        XCTAssertTrue(store.toast?.text.contains("unavailable") ?? false)
    }

    @MainActor
    func testSnapshotOmitsUnmeasuredMetricsAndPrivateIdentifiers() async throws {
        let store = MonitorStore(startPolling: false)
        let empty = store.diagnosticSnapshot(capturedAt: base)
        XCTAssertNil(empty.cpuPercent)
        XCTAssertNil(empty.memoryTotalBytes)
        XCTAssertNil(empty.networkDownloadBytesPerSecond)
        XCTAssertNil(empty.batteryChargePercent)
        store.applyNetwork(network(100, at: base))
        store.applyNetwork(network(140, at: base.addingTimeInterval(2)))
        store.selectedNetworkInterfaceID = "en0"
        store.power = PowerInfo(
            hasBattery: true, chargePercent: 78, hasChargeReading: true, lowPowerModeEnabled: true)
        let measured = store.diagnosticSnapshot(capturedAt: base.addingTimeInterval(3))
        XCTAssertEqual(measured.networkDownloadBytesPerSecond, 20)
        XCTAssertEqual(measured.batteryChargePercent, 78)
        XCTAssertEqual(measured.lowPowerModeEnabled, true)
        let json = String(decoding: try DiagnosticsExport.encode(snapshot: measured, format: .json), as: UTF8.self)
        XCTAssertFalse(json.contains("192.0.2.1"))
        XCTAssertFalse(json.contains("en0"))
        XCTAssertFalse(json.contains("Wi-Fi"))
        XCTAssertEqual(measured.capturedAt, base.addingTimeInterval(3))
    }

    @MainActor
    func testExportHistoryUsesFiveMinuteWindowAndDistinctCSVRowTypes() async throws {
        let store = MonitorStore(startPolling: false)
        store.cpuUsage = 25
        store.perCoreCPU = [25]
        store.cpuHistory = [25]
        store.cpuTimeline.record(50, at: base.addingTimeInterval(-301))
        store.cpuTimeline.record(25, at: base)
        let snapshot = store.diagnosticSnapshot(capturedAt: base)
        let rows = try XCTUnwrap(snapshot.history)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.timestamp, base)
        XCTAssertEqual(rows.first?.metric, .cpuPercent)
        let csv = String(decoding: try DiagnosticsExport.encode(snapshot: snapshot, format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains(",cpuPercent,percent,25.0,snapshot\r\n"))
        XCTAssertTrue(csv.contains(",cpuPercent,percent,25.0,history\r\n"))
    }

    @MainActor
    func testUnavailableCPUAndMemoryDoNotInventTimelinePoints() async {
        let store = MonitorStore(startPolling: false)
        store.applySample(
            cpu: .init(perCore: []),
            memory: MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: 0),
            io: DiskIOSnapshot(timestamp: base), power: nil,
            net: network(100, at: base), disk: nil, info: nil)
        XCTAssertNil(store.cpuTimeline.latestTimestamp)
        XCTAssertNil(store.memoryTimeline.latestTimestamp)
        XCTAssertNil(store.diagnosticSnapshot(capturedAt: base).cpuPercent)
        XCTAssertNil(store.diagnosticSnapshot(capturedAt: base).memoryTotalBytes)
    }

    @MainActor
    func testCPUAndMemoryCaptureTimestampsAndPowerIgnoresUnsupportedWatts() async {
        let store = MonitorStore(startPolling: false)
        let memory = MemoryBreakdown(app: 40, wired: 20, compressed: 10, cached: 20, free: 10, total: 100)
        store.applySample(
            cpu: .init(perCore: [10, 30]), memory: memory,
            io: DiskIOSnapshot(timestamp: base), power: nil,
            net: network(100, at: base), disk: nil, info: nil)
        XCTAssertEqual(store.latestSampleAt, base)
        XCTAssertEqual(store.cpuTimeline.points(in: .fiveMinutes, endingAt: base).last?.value, 20)
        XCTAssertEqual(store.memoryTimeline.points(in: .fiveMinutes, endingAt: base).last?.value, 70)
        store.applyPower(PowerInfo(systemPowerWatts: .nan), at: base)
        XCTAssertTrue(store.powerDrawTimeline.points(in: .fiveMinutes, endingAt: base).isEmpty)
        store.applyPower(PowerInfo(systemPowerWatts: 8.4), at: base.addingTimeInterval(5))
        XCTAssertEqual(store.powerDrawTimeline.latestTimestamp, base.addingTimeInterval(5))
    }
}
