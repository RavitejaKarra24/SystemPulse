import AppKit
import Darwin
import SwiftUI
import XCTest

@testable import SystemPulse

final class NetworkInterfacesTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 100)

    private func snapshot(
        _ name: String = "en0", input: UInt64 = 100, output: UInt64 = 200, active: Bool = true,
        addresses: [String] = ["192.0.2.1"]
    ) -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            name: name, displayName: "Adapter \(name)", addresses: addresses, isActive: active,
            kind: .ethernet, bytesIn: input, bytesOut: output
        )
    }

    private func record(
        _ name: String = "en0", family: Int32 = AF_LINK, flags: UInt32 = UInt32(IFF_UP | IFF_RUNNING),
        input: UInt64? = 100, output: UInt64 = 200, address: String? = nil
    ) -> NetworkInterfaceSampler.Record {
        NetworkInterfaceSampler.Record(
            name: name, family: UInt8(family), flags: flags,
            counters: input.map { ByteCounters(first: $0, second: output) }, address: address
        )
    }

    func testGroupsLinkCountersOnceAndDeduplicatesSortedAddresses() throws {
        let samples = NetworkInterfaceSampler.snapshots(
            from: [
                record(family: AF_INET6, input: 9999, address: "2001:db8::1"),
                record(), record(input: 9999),
                record(family: AF_INET, address: "192.0.2.1"),
                record(family: AF_INET, address: "192.0.2.1"),
            ], metadata: ["en0": .init(displayName: "Wi-Fi", kind: .wifi)])
        let interface = try XCTUnwrap(samples.first)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(interface.id, "en0")
        XCTAssertEqual(interface.name, "en0")
        XCTAssertEqual(interface.displayName, "Wi-Fi")
        XCTAssertEqual(interface.kind, .wifi)
        XCTAssertEqual(interface.addresses, ["192.0.2.1", "2001:db8::1"])
        XCTAssertEqual(interface.bytesIn, 100)
        XCTAssertEqual(interface.bytesOut, 200)
        XCTAssertTrue(interface.isActive)
    }

    func testPhysicalScopeAndMissingCounters() {
        let excluded = ["lo0", "bridge0", "utun0", "awdl0", "llw0", "pdp_ip0"]
        let records =
            excluded.map { record($0) } + [
                record("en2"), record("en1"),
                record("en3", family: AF_INET, address: "192.0.2.3"),
                record("en4", input: nil),
            ]
        let samples = NetworkInterfaceSampler.snapshots(from: records)
        XCTAssertEqual(samples.map(\.id), ["en1", "en2"])
        XCTAssertEqual(samples.first?.displayName, "en1")
        XCTAssertEqual(samples.first?.kind, .physical, "Never assume en0/en1 is Wi-Fi")
        XCTAssertFalse(SystemSampler.isPhysicalNetworkInterface("pdp_ip0", family: UInt8(AF_LINK)))
    }

    func testActiveRequiresBothUpAndRunningLinkFlags() {
        let samples = NetworkInterfaceSampler.snapshots(from: [
            record("en0", flags: UInt32(IFF_UP)),
            record("en1", flags: UInt32(IFF_RUNNING)),
            record("en2", flags: 0), record("en3"),
            record("en0", family: AF_INET, address: "192.0.2.1"),
        ])
        XCTAssertEqual(samples.map(\.isActive), [false, false, false, true])
    }

    func testExtractsNumericIPv4AndIPv6WithLocalScopeWithoutDNS() {
        var ipv4 = sockaddr_in()
        ipv4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        ipv4.sin_family = UInt8(AF_INET)
        XCTAssertEqual(inet_pton(AF_INET, "192.0.2.42", &ipv4.sin_addr), 1)
        let v4 = withUnsafePointer(to: &ipv4) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                NetworkInterfaceSampler.localAddress($0, interfaceName: "en0")
            }
        }
        XCTAssertEqual(v4, "192.0.2.42")

        var ipv6 = sockaddr_in6()
        ipv6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        ipv6.sin6_family = UInt8(AF_INET6)
        XCTAssertEqual(inet_pton(AF_INET6, "fe80::1234", &ipv6.sin6_addr), 1)
        ipv6.sin6_scope_id = 7
        let scoped = withUnsafePointer(to: &ipv6) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                NetworkInterfaceSampler.localAddress($0, interfaceName: "en7")
            }
        }
        XCTAssertEqual(scoped, "fe80::1234%en7")
        ipv6.sin6_scope_id = 0
        XCTAssertEqual(inet_pton(AF_INET6, "2001:db8::42", &ipv6.sin6_addr), 1)
        let v6 = withUnsafePointer(to: &ipv6) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                NetworkInterfaceSampler.localAddress($0, interfaceName: "en0")
            }
        }
        XCTAssertEqual(v6, "2001:db8::42")
        var link = sockaddr()
        link.sa_family = UInt8(AF_LINK)
        XCTAssertNil(withUnsafePointer(to: &link) { NetworkInterfaceSampler.localAddress($0, interfaceName: "en0") })
    }

    func testFirstSampleBaselinesAndElapsedTimeSetsIndependentRates() throws {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot(), snapshot("en1", input: 1000)], at: epoch)
        XCTAssertEqual(tracker.interfaces.map(\.inRate), [0, 0])
        XCTAssertEqual(tracker.interfaces.map(\.sessionBytesIn), [0, 0])
        tracker.apply(
            [
                snapshot(input: 150, output: 210), snapshot("en1", input: 1200, output: 300),
            ], at: epoch.addingTimeInterval(2.5))
        let first = try XCTUnwrap(tracker.interfaces.first)
        XCTAssertEqual(first.inRate, 20, accuracy: 0.0001)
        XCTAssertEqual(first.outRate, 4, accuracy: 0.0001)
        XCTAssertEqual(first.sessionBytesIn, 50)
        XCTAssertEqual(first.sessionBytesOut, 10)
        XCTAssertEqual(tracker.interfaces.last?.inRate, 80)
        XCTAssertEqual(tracker.interfaces.last?.sessionBytesOut, 100)
    }

    func testCounterResetIsPerDirectionAndPreservesSessionTotals() throws {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot()], at: epoch)
        tracker.apply([snapshot(input: 200, output: 300)], at: epoch.addingTimeInterval(1))
        tracker.apply([snapshot(input: 5, output: 350)], at: epoch.addingTimeInterval(2))
        let reset = try XCTUnwrap(tracker.interfaces.first)
        XCTAssertEqual(reset.inRate, 0)
        XCTAssertEqual(reset.outRate, 50)
        XCTAssertEqual(reset.sessionBytesIn, 100)
        XCTAssertEqual(reset.sessionBytesOut, 150)
        tracker.apply([snapshot(input: 25, output: 10)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 20)
        XCTAssertEqual(tracker.interfaces.first?.outRate, 0)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 120)
    }

    func testRemovalClearsRatesAndAddressesAndReconnectBaselines() throws {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot(), snapshot("en1")], at: epoch)
        tracker.apply([snapshot(input: 200), snapshot("en1", input: 300)], at: epoch.addingTimeInterval(1))
        tracker.apply([snapshot("en1", input: 400)], at: epoch.addingTimeInterval(2))
        let removed = try XCTUnwrap(tracker.interfaces.first)
        XCTAssertFalse(removed.isPresent)
        XCTAssertFalse(removed.isActive)
        XCTAssertTrue(removed.addresses.isEmpty)
        XCTAssertEqual(removed.inRate, 0)
        XCTAssertEqual(removed.sessionBytesIn, 100)
        XCTAssertEqual(removed.displayName, "Adapter en0")
        XCTAssertEqual(tracker.interfaces.last?.inRate, 100)
        tracker.apply([snapshot(input: 50_000), snapshot("en1", input: 500)], at: epoch.addingTimeInterval(3))
        XCTAssertTrue(try XCTUnwrap(tracker.interfaces.first).isPresent)
        XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 100)
        tracker.apply([snapshot(input: 50_050)], at: epoch.addingTimeInterval(4))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 50)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 150)
    }

    func testInactiveLinkClearsBaselineAndDoesNotCountDowntimeTraffic() {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot()], at: epoch)
        tracker.apply([snapshot(input: 200)], at: epoch.addingTimeInterval(1))
        tracker.apply([snapshot(input: 500, active: false)], at: epoch.addingTimeInterval(2))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 100)
        tracker.apply([snapshot(input: 10_000)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
        tracker.apply([snapshot(input: 10_060)], at: epoch.addingTimeInterval(5))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 30)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 160)
    }

    func testNewInterfaceAndDuplicateSnapshotNeverCreateSinceBootSpike() {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot()], at: epoch)
        tracker.apply(
            [
                snapshot(input: 150), snapshot(input: 9999), snapshot("en1", input: 1_000_000),
            ], at: epoch.addingTimeInterval(1))
        XCTAssertEqual(tracker.interfaces.count, 2)
        XCTAssertEqual(tracker.interfaces.first?.inRate, 50)
        XCTAssertEqual(tracker.interfaces.last?.inRate, 0)
    }

    func testInvalidElapsedTimeClearsRatesWithoutConsumingBaselineOrMetadata() {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot()], at: epoch)
        tracker.apply([snapshot(input: 200)], at: epoch.addingTimeInterval(1))
        for time in [epoch, epoch.addingTimeInterval(1), Date(timeIntervalSince1970: .nan)] {
            tracker.apply([snapshot(input: 9999, active: false)], at: time)
            XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
            XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 100)
            XCTAssertTrue(tracker.interfaces.first?.isActive ?? false)
        }
        tracker.apply([snapshot(input: 260)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 30)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 160)
    }

    func testNonfiniteFirstTimestampAndOverflowingElapsedDoNotConsumeSamples() {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot()], at: Date(timeIntervalSince1970: .infinity))
        tracker.apply([snapshot()], at: Date(timeIntervalSince1970: .nan))
        XCTAssertTrue(tracker.interfaces.isEmpty)
        let early = Date(timeIntervalSince1970: -Double.greatestFiniteMagnitude)
        tracker.apply([snapshot()], at: early)
        tracker.apply([snapshot(input: 9999)], at: Date(timeIntervalSince1970: Double.greatestFiniteMagnitude))
        XCTAssertEqual(tracker.interfaces.first?.bytesIn, 100)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 0)
    }

    func testLongElapsedTimeUsesElapsedSecondsNotPollingInterval() {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot(input: 0)], at: epoch)
        tracker.apply([snapshot(input: 3600)], at: epoch.addingTimeInterval(3600))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 1)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 3600)
    }

    func testSessionTotalsSaturateWithoutOverflow() {
        var tracker = NetworkInterfaceTracker()
        tracker.apply([snapshot(input: 0, output: 0)], at: epoch)
        tracker.apply([snapshot(input: .max, output: .max)], at: epoch.addingTimeInterval(1))
        tracker.apply([snapshot(input: 0, output: 0)], at: epoch.addingTimeInterval(2))
        tracker.apply([snapshot(input: 1, output: 1)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, .max)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesOut, .max)
    }

    func testDisconnectedMetadataIsBoundedByTimeAndCount() {
        var tracker = NetworkInterfaceTracker(disconnectedRetention: 10, maxDisconnectedInterfaces: 2)
        tracker.apply([snapshot("en0"), snapshot("en1"), snapshot("en2")], at: epoch)
        tracker.apply([], at: epoch.addingTimeInterval(1))
        XCTAssertEqual(tracker.interfaces.map(\.id), ["en0", "en1"])
        tracker.apply([snapshot("en3")], at: epoch.addingTimeInterval(9))
        XCTAssertEqual(tracker.interfaces.count, 3)
        tracker.apply([snapshot("en3")], at: epoch.addingTimeInterval(10))
        XCTAssertEqual(tracker.interfaces.map(\.id), ["en3"])
    }

    func testReconnectAfterRetentionExpiresStartsNewSession() {
        var tracker = NetworkInterfaceTracker(disconnectedRetention: 2)
        tracker.apply([snapshot()], at: epoch)
        tracker.apply([snapshot(input: 200)], at: epoch.addingTimeInterval(1))
        tracker.apply([], at: epoch.addingTimeInterval(2))
        tracker.apply([snapshot(input: 1000)], at: epoch.addingTimeInterval(3))
        XCTAssertEqual(tracker.interfaces.first?.inRate, 0)
        XCTAssertEqual(tracker.interfaces.first?.sessionBytesIn, 0)
    }

    func testZeroRetentionAndCapKeepPresentInterfacesButNoRemovedMetadata() {
        var tracker = NetworkInterfaceTracker(disconnectedRetention: 0, maxDisconnectedInterfaces: 0)
        tracker.apply([snapshot(), snapshot("en1", active: false)], at: epoch)
        tracker.apply([snapshot("en1", active: false)], at: epoch.addingTimeInterval(1))
        XCTAssertEqual(tracker.interfaces.map(\.id), ["en1"])
    }

    func testReadingExposesMetadataAndSuppressesInactiveRates() {
        let inactive = NetworkInterfaceReading(snapshot: snapshot(active: false), inRate: 100, outRate: 200)
        XCTAssertEqual(inactive.name, "en0")
        XCTAssertEqual(inactive.bytesIn, 100)
        XCTAssertEqual(inactive.bytesOut, 200)
        XCTAssertEqual(inactive.kind, .ethernet)
        XCTAssertEqual(inactive.inRate, 0)
        let missing = NetworkInterfaceReading(snapshot: snapshot(), isPresent: false, inRate: 100, outRate: 200)
        XCTAssertFalse(missing.isActive)
        XCTAssertEqual(missing.outRate, 0)
    }

    func testReadOnlyLiveSamplerReturnsUniquePhysicalInterfaces() {
        let samples = NetworkInterfaceSampler.sample()
        XCTAssertEqual(Set(samples.map(\.id)).count, samples.count)
        for interface in samples {
            XCTAssertTrue(interface.name.hasPrefix("en"))
            XCTAssertFalse(interface.displayName.isEmpty)
            XCTAssertEqual(Set(interface.addresses).count, interface.addresses.count)
        }
    }

    @MainActor
    func testCardRendersAllSelectedEmptyAndDisconnectedStatesInBothAppearances() async throws {
        let active = NetworkInterfaceReading(snapshot: snapshot(), inRate: 1000, sessionBytesIn: 5000)
        let inactive = NetworkInterfaceReading(snapshot: snapshot("en1", active: false, addresses: []))
        let missing = NetworkInterfaceReading(snapshot: snapshot("en2", active: false, addresses: []), isPresent: false)
        let readings = [active, inactive, missing]
        let states: [([NetworkInterfaceReading], String?)] = [
            (readings, nil), (readings, "en0"), (readings, "en1"), (readings, "en2"),
            ([], nil), ([], "en9"),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (interfaces, selection) in states {
                let view = NetworkInterfacesCard(interfaces: interfaces, selection: .constant(selection))
                    .padding(20)
                    .frame(width: 320)
                    .environment(\.colorScheme, scheme)
                let hosting = NSHostingView(rootView: view)
                let frame = NSRect(x: 0, y: 0, width: 320, height: 1400)
                let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = hosting
                hosting.frame = frame
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                window.close()
            }
        }
    }
}
