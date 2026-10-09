import Darwin
import XCTest

@testable import SystemPulse

final class MonitorStoreTests: XCTestCase {
    private func process(_ pid: pid_t) -> ProcessStat {
        ProcessStat(
            id: pid, name: "Fixture", executablePath: "/fixture", bundlePath: nil,
            bundleIdentifier: nil, cpu: 0, memory: 0, threadCount: 1, iconKey: "fixture")
    }

    private func group(_ pids: [pid_t], system: Bool = false) -> ProcessGroup {
        ProcessGroup(
            id: system ? "system" : "fixture", name: "Fixture", iconKey: nil,
            isSystemGroup: system, processes: pids.map(process))
    }

    private func item(_ path: String, bytes: UInt64 = 10, safe: Bool = true) -> DiskItem {
        DiskItem(
            id: path, name: "Fixture", path: path, bytes: bytes, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: safe, safetyNote: "Fixture")
    }

    @MainActor
    func testProcessSamplingPublishesOneRevisionPerPassEvenWhenUnchanged() async {
        let store = MonitorStore(startPolling: false)
        let groups = [group([12345])]
        store.applyProcesses(groups)
        XCTAssertEqual(store.processSampleRevision, 1)
        XCTAssertEqual(store.topProcessName, "Fixture")
        store.applyProcesses(groups)
        XCTAssertEqual(store.processSampleRevision, 2)
        store.applyProcesses([])
        XCTAssertEqual(store.processSampleRevision, 3)
        XCTAssertEqual(store.topProcessName, "—")
    }

    @MainActor
    func testNoPollingInitAlsoDisablesVisibilityAndRestartSampling() async {
        let store = MonitorStore(startPolling: false)
        store.isPanelVisible = true
        store.restartPolling()
        await Task.yield()
        XCTAssertTrue(store.cpuHistory.isEmpty)
        XCTAssertTrue(store.memoryHistory.isEmpty)
        XCTAssertTrue(store.processGroups.isEmpty)
    }

    @MainActor
    func testQuitProtectsInvalidPIDLaunchdAndSelfBeforeAnyOSCall() async {
        var calls = 0
        let actions = ProcessActions(
            applicationRequest: { _, _ in
                calls += 1
                return nil
            },
            signalRequest: { _, _ in
                calls += 1
                return 0
            }, ownPID: 42)
        let store = MonitorStore(startPolling: false, processActions: actions)
        for pid: pid_t in [-1, -100, 0, 1, 42] {
            store.quit(pid: pid, force: true)
            XCTAssertEqual(store.toast?.isError, true)
        }
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testSystemGroupAndKnownSystemProcessAreProtected() async {
        var calls = 0
        let actions = ProcessActions(
            applicationRequest: { _, _ in
                calls += 1
                return true
            },
            signalRequest: { _, _ in
                calls += 1
                return 0
            }, ownPID: 42)
        let store = MonitorStore(startPolling: false, processActions: actions)
        let system = group([100, 101], system: true)
        store.processGroups = [system]
        store.quitGroup(system, force: false)
        XCTAssertEqual(store.toast?.isError, true)
        store.quit(pid: 100, force: true)
        XCTAssertEqual(store.toast?.isError, true)
        store.quitGroup(group([100, 101]), force: true)  // cannot bypass protection by relabeling a group
        XCTAssertEqual(store.toast?.isError, true)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testGroupContainingSelfIsRejectedAtomically() async {
        var calls = 0
        let actions = ProcessActions(
            applicationRequest: { _, _ in
                calls += 1
                return true
            },
            signalRequest: { _, _ in
                calls += 1
                return 0
            }, ownPID: 42)
        let store = MonitorStore(startPolling: false, processActions: actions)
        store.quitGroup(group([100, 42]), force: true)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.toast?.isError, true)
    }

    @MainActor
    func testApplicationRefusalIsAnErrorWithoutEscalationToSignal() async {
        var signals = 0
        let actions = ProcessActions(
            applicationRequest: { _, _ in false },
            signalRequest: { _, _ in
                signals += 1
                return 0
            }, ownPID: 42)
        let store = MonitorStore(startPolling: false, processActions: actions)
        for force in [false, true] {
            store.quit(pid: 100, force: force)
            XCTAssertEqual(store.toast?.isError, true)
            XCTAssertEqual(store.toast?.text, "Application refused the quit request")
        }
        XCTAssertEqual(signals, 0)
    }

    @MainActor
    func testSignalFailuresReportPermissionAndDisappearedProcess() async {
        for (code, message) in [(EPERM, "Permission denied"), (ESRCH, "Process is no longer running")] {
            let actions = ProcessActions(
                applicationRequest: { _, _ in nil },
                signalRequest: { _, _ in code }, ownPID: 42)
            let store = MonitorStore(startPolling: false, processActions: actions)
            store.quit(pid: 100, force: false)
            XCTAssertEqual(store.toast?.isError, true)
            XCTAssertEqual(store.toast?.text, message)
        }
    }

    @MainActor
    func testSignalSuccessReportsRequestNotExitAndUsesRightSignal() async {
        var received: [Int32] = []
        let actions = ProcessActions(
            applicationRequest: { _, _ in nil },
            signalRequest: { _, signal in
                received.append(signal)
                return 0
            }, ownPID: 42)
        let store = MonitorStore(startPolling: false, processActions: actions)
        store.quit(pid: 100, force: false)
        XCTAssertEqual(store.toast?.text, "Quit requested")
        XCTAssertEqual(store.toast?.isError, false)
        store.quit(pid: 100, force: true)
        XCTAssertEqual(store.toast?.text, "Force quit requested")
        XCTAssertEqual(received, [SIGTERM, SIGKILL])
    }

    @MainActor
    func testGroupReportsPartialFailureAndDeduplicatesPIDs() async {
        var received: [pid_t] = []
        let actions = ProcessActions(
            applicationRequest: { _, _ in nil },
            signalRequest: { pid, _ in
                received.append(pid)
                return pid == 100 ? EPERM : 0
            }, ownPID: 42)
        let store = MonitorStore(startPolling: false, processActions: actions)
        store.quitGroup(group([100, 101, 101]), force: false)
        XCTAssertEqual(received, [100, 101])
        XCTAssertEqual(store.toast?.isError, true)
        XCTAssertEqual(store.toast?.text, "Quit: 1 requested, 1 failed · Permission denied")
    }

    @MainActor
    func testEmptyGroupDoesNotClaimSuccess() async {
        let store = MonitorStore(startPolling: false)
        store.quitGroup(group([]), force: false)
        XCTAssertEqual(store.toast?.isError, true)
        XCTAssertEqual(store.toast?.text, "No processes to quit")
    }

    @MainActor
    func testStoreRateHistoryPeaksAndSessionTotalsAreBoundedAndResetSafe() async {
        let store = MonitorStore(startPolling: false)
        let epoch = Date(timeIntervalSince1970: 100)
        for i in 0...65 {
            let count = UInt64(i * 100)
            let time = epoch.addingTimeInterval(Double(i * 2))
            store.applyNetwork(NetworkSnapshot(bytesIn: count, bytesOut: count * 2, timestamp: time))
            store.applyDiskIO(DiskIOSnapshot(bytesRead: count, bytesWritten: count * 3, timestamp: time))
        }
        XCTAssertEqual(store.netInRate, 50)
        XCTAssertEqual(store.netOutRate, 100)
        XCTAssertEqual(store.netInPeak, 50)
        XCTAssertEqual(store.diskReadPeak, 50)
        XCTAssertEqual(store.diskWritePeak, 150)
        XCTAssertEqual(store.sessionBytesIn, 6500)
        XCTAssertEqual(store.sessionBytesWritten, 19500)
        for history in [
            store.netHistory, store.netInHistory, store.netOutHistory, store.diskReadHistory, store.diskWriteHistory,
        ] {
            XCTAssertEqual(history.count, MonitorStore.historyLimit)
        }
        store.applyNetwork(NetworkSnapshot(bytesIn: 1, bytesOut: 1, timestamp: epoch.addingTimeInterval(132)))
        store.applyDiskIO(DiskIOSnapshot(bytesRead: 1, bytesWritten: 1, timestamp: epoch.addingTimeInterval(132)))
        XCTAssertEqual(store.netInRate, 0)
        XCTAssertEqual(store.diskWriteRate, 0)
        XCTAssertEqual(store.sessionBytesIn, 6500)
        XCTAssertEqual(store.sessionBytesWritten, 19500)
    }

    @MainActor
    func testDeletionRejectsUnsafeUnscannedAndScanningItemsBeforeTrash() async {
        var calls = 0
        let store = MonitorStore(
            startPolling: false,
            trashItem: { _ in
                calls += 1
                return true
            })
        store.lastScanComplete = true
        let unsafe = item("/fixture/unsafe", safe: false)
        let safe = item("/fixture/safe")
        store.diskCategories = [
            DiskCategory(id: "fixture", name: "Fixture", icon: "", bytes: 20, items: [unsafe, safe])
        ]
        XCTAssertFalse(store.deleteDiskItem(unsafe))
        XCTAssertFalse(store.deleteDiskItem(item("/fixture/unsafe")))  // forged safety flag
        XCTAssertFalse(store.deleteDiskItem(item("/fixture/missing")))
        store.isScanning = true
        XCTAssertFalse(store.deleteDiskItem(safe))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.toast?.isError, true)
    }

    @MainActor
    func testReclaimableBytesExcludesProtectedData() async {
        let store = MonitorStore(startPolling: false)
        let safe = item("/fixture/cache", bytes: 10)
        let unsafe = item("/fixture/data", bytes: 100, safe: false)
        store.diskCategories = [
            DiskCategory(id: "fixture", name: "Fixture", icon: "", bytes: 110, items: [safe, unsafe])
        ]
        XCTAssertEqual(store.reclaimableBytes, 10)
    }

    @MainActor
    func testDeletionFailureKeepsMeasurementsAndSuccessRecomputesCategories() async {
        var succeed = false
        var received: [String] = []
        let store = MonitorStore(
            startPolling: false,
            trashItem: { item in
                received.append(item.path)
                return succeed
            })
        store.lastScanComplete = true
        let first = item("/fixture/first", bytes: 10)
        let second = item("/fixture/second", bytes: 20)
        store.diskCategories = [
            DiskCategory(id: "fixture", name: "Fixture", icon: "", bytes: 30, items: [first, second])
        ]
        XCTAssertFalse(store.deleteDiskItem(first))
        XCTAssertEqual(store.diskCategories.first?.bytes, 30)
        XCTAssertEqual(store.toast?.isError, true)
        // Acknowledge retained failure feedback before this explicit retry.
        if let failure = store.toast { store.dismissToast(id: failure.id) }
        XCTAssertNil(store.toast)
        succeed = true
        XCTAssertTrue(store.deleteDiskItem(first))
        XCTAssertEqual(store.diskCategories.first?.bytes, 20)
        XCTAssertEqual(store.diskCategories.first?.items.map(\.id), [second.id])
        XCTAssertEqual(store.toast?.isError, false)
        XCTAssertTrue(store.deleteDiskItem(second))
        XCTAssertTrue(store.diskCategories.isEmpty)
        XCTAssertEqual(received, [first.path, first.path, second.path])
    }
}
