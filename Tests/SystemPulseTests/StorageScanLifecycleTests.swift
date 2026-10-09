import Foundation
import XCTest

@testable import SystemPulse

/// Synchronous scanner callbacks cannot await an actor. All recorder state is
/// protected by one lock; snapshots are copied out while holding that lock.
final class ScanUpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [DiskScanner.ScanUpdate] = []
    var updates: [DiskScanner.ScanUpdate] { lock.withLock { recorded } }
    func append(_ update: DiskScanner.ScanUpdate) { lock.withLock { recorded.append(update) } }
}

/// Test-only blocking worker gate. The condition guards every mutable field;
/// it controls a mock scan, never the user's filesystem or telemetry.
private final class ScanWorkerGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var starts = 0
    let started = XCTestExpectation(description: "Mock scan worker started")
    var startCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return starts
    }
    func wait() {
        condition.lock()
        starts += 1
        if starts == 1 { started.fulfill() }
        while !released { condition.wait() }
        condition.unlock()
    }
    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class ScanWeakStoreReference {
    weak var value: MonitorStore?
    init(_ value: MonitorStore?) { self.value = value }
}

final class StorageScanLifecycleTests: XCTestCase {
    private static var category: DiskCategory {
        let item = DiskItem(
            id: "/fixture/cache", name: "Fixture", path: "/fixture/cache", bytes: 8192, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Test cache")
        return DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: item.bytes, items: [item])
    }

    @MainActor
    func testCancelRejectsLateUpdatesAndRescanWaitsForWorkerExit() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ScanWorkerGate()
        defer { gate.release() }
        let category = Self.category
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            scanRunner: { update in
                gate.wait()
                // Deliberately ignore cancellation, just like an OS query that was
                // already in flight. These late results must not publish.
                update(.init(currentPath: "/late", categories: [category], progress: 0.9, isComplete: false))
                update(.init(currentPath: "", categories: [category], progress: 1, isComplete: true))
            })
        store.scanDisk()
        await fulfillment(of: [gate.started], timeout: 2)
        store.cancelDiskScan()
        store.cancelDiskScan()
        XCTAssertTrue(store.isCancellingScan)
        XCTAssertTrue(store.isScanning)
        store.scanDisk()
        XCTAssertEqual(gate.startCount, 1, "Do not start a second filesystem walk while the first is stopping")
        gate.release()
        await store.waitForDiskScan()
        XCTAssertFalse(store.isScanning)
        XCTAssertFalse(store.lastScanComplete)
        XCTAssertTrue(store.lastScanCancelled)
        XCTAssertTrue(store.scanResultsArePartial)
        XCTAssertTrue(store.diskCategories.isEmpty, "Late completions cannot replace the cancelled snapshot")
        store.scanDisk()
        await store.waitForDiskScan()
        XCTAssertEqual(gate.startCount, 2)
        XCTAssertTrue(store.lastScanComplete)
        XCTAssertFalse(store.scanResultsArePartial)
        XCTAssertEqual(store.diskCategories.first?.bytes, 8192)
    }

    @MainActor
    func testSkippedLocationsDisableAllTrashEntryPointsAndRescanClearsPartialState() async throws {
        let fixture = try SettingsPreferencesFixture()
        let category = Self.category
        let recorder = ScanUpdateRecorder()
        var trashCalls = 0
        let store = MonitorStore(
            startPolling: false,
            trashItem: { _ in
                trashCalls += 1
                return true
            },
            preferences: fixture.makePreferences(),
            scanRunner: { update in
                let result = DiskScanner.ScanUpdate(
                    currentPath: "", categories: [category], progress: 1, isComplete: true,
                    skippedLocationCount: recorder.updates.isEmpty ? 2 : 0)
                recorder.append(result)
                update(result)
            })
        store.scanDisk()
        await store.waitForDiskScan()
        XCTAssertTrue(store.lastScanComplete)
        XCTAssertEqual(store.scanSkippedLocationCount, 2)
        XCTAssertTrue(store.scanResultsArePartial)
        XCTAssertFalse(store.deleteDiskItem(category.items[0]))
        XCTAssertEqual(trashCalls, 0)
        XCTAssertTrue(store.toast?.text.contains("read-only") == true)
        store.scanDisk()
        await store.waitForDiskScan()
        XCTAssertFalse(store.scanResultsArePartial)
        XCTAssertEqual(store.scanSkippedLocationCount, 0)
        XCTAssertTrue(store.deleteDiskItem(category.items[0]))
        XCTAssertEqual(trashCalls, 1)
    }

    @MainActor
    func testShutdownCancelsWorkerAndCannotStartAnotherScan() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ScanWorkerGate()
        defer { gate.release() }
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(), scanRunner: { _ in gate.wait() })
        store.scanDisk()
        await fulfillment(of: [gate.started], timeout: 2)
        store.stopPolling()
        XCTAssertTrue(store.isCancellingScan)
        gate.release()
        await store.waitForDiskScan()
        store.scanDisk()
        XCTAssertEqual(gate.startCount, 1)
        XCTAssertTrue(store.lastScanCancelled)
    }

    @MainActor
    func testWorkerWithoutTerminalUpdateIsReadOnlyNotSuccessfulEmptyScan() async throws {
        let fixture = try SettingsPreferencesFixture()
        let category = Self.category
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            scanRunner: { update in
                update(.init(currentPath: "/fixture", categories: [category], progress: 0.5, isComplete: false))
            })
        store.scanDisk()
        await store.waitForDiskScan()
        XCTAssertFalse(store.lastScanComplete)
        XCTAssertTrue(store.scanResultsArePartial)
    }

    @MainActor
    func testActiveScanDoesNotRetainDiscardedStore() async throws {
        let fixture = try SettingsPreferencesFixture()
        let gate = ScanWorkerGate()
        defer { gate.release() }
        var store: MonitorStore? = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(), scanRunner: { _ in gate.wait() })
        let weakStore = ScanWeakStoreReference(store)
        store?.scanDisk()
        await fulfillment(of: [gate.started], timeout: 2)
        store = nil
        XCTAssertNil(weakStore.value)
        gate.release()
    }
}
