import Foundation
import XCTest

@testable import SystemPulse

/// Single lock guards every mutable field. A synchronous filesystem mock cannot
/// await an actor; no real Trash operations are performed by this recorder.
private final class CleanupClientRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [DiskItem] = []
    var items: [DiskItem] { lock.withLock { recorded } }
    func record(_ item: DiskItem) { lock.withLock { recorded.append(item) } }
}

/// Test-only condition, not a production filesystem gate. Lets Stop arrive while
/// a mock OS request is in flight; all state is condition-protected.
private final class CleanupWorkerGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    let started = XCTestExpectation(description: "Mock Trash call started")
    func wait() {
        condition.lock()
        started.fulfill()
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

final class CleanupQueueTests: XCTestCase {
    private func item(_ index: Int, safe: Bool = true) -> DiskItem {
        DiskItem(
            id: "/fixture/cache-\(index)", name: "Cache \(index)", path: "/fixture/cache-\(index)",
            bytes: UInt64(index + 1) * 100, fileCount: 1, isDirectory: true, categoryName: "Fixture",
            safeToDelete: safe, safetyNote: "Quit owning app before clearing.")
    }

    @MainActor
    private func store(_ items: [DiskItem], client: CleanupTrashClient = .init(move: { _ in .movedToTrash })) throws
        -> MonitorStore
    {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            scanRunner: { update in
                update(.init(currentPath: "", categories: [], progress: 1, isComplete: true))
            },
            folderScanRunner: { _, update in
                update(.init(currentPath: "", categories: [], progress: 1, isComplete: true))
            }, cleanupTrashClient: client, cleanupEligibility: { $0.safeToDelete })
        store.lastScanComplete = true
        store.diskCategories = [
            DiskCategory(
                id: "fixture", name: "Fixture", icon: "folder", bytes: CleanupQueue.totalBytes(items), items: items)
        ]
        return store
    }

    @MainActor
    func testQueueAndReviewDoNotMoveAnythingAndCancelPreservesSelection() throws {
        let recorder = CleanupClientRecorder()
        let entry = item(0)
        let store = try store(
            [entry],
            client: .init(move: {
                recorder.record($0)
                return .movedToTrash
            }))
        XCTAssertTrue(store.queueCleanupItem(entry))
        XCTAssertTrue(store.queueCleanupItem(entry))
        XCTAssertEqual(store.cleanupQueue.count, 1)
        let review = try XCTUnwrap(store.prepareCleanupReview())
        XCTAssertTrue(store.canConfirmCleanup(review))
        XCTAssertTrue(recorder.items.isEmpty)
        store.dismissCleanupReview(review)
        XCTAssertFalse(store.canConfirmCleanup(review))
        XCTAssertFalse(store.confirmCleanup(review))
        XCTAssertEqual(store.cleanupQueue, [entry])
        XCTAssertTrue(recorder.items.isEmpty)
    }

    @MainActor
    func testQueueIsBoundedAndRejectsUnscannedUnsafeAndForgedMeasurements() throws {
        let entries = (0..<51).map { item($0) }
        let store = try store(entries + [item(99, safe: false)])
        XCTAssertFalse(store.queueCleanupItem(item(99)))
        XCTAssertFalse(store.queueCleanupItem(item(1000)))
        var forged = entries[0]
        forged = DiskItem(
            id: forged.id, name: forged.name, path: forged.path, bytes: 42, fileCount: 1,
            isDirectory: true, categoryName: forged.categoryName, safeToDelete: true, safetyNote: forged.safetyNote)
        XCTAssertFalse(store.queueCleanupItem(forged))
        for entry in entries.prefix(50) { XCTAssertTrue(store.queueCleanupItem(entry)) }
        XCTAssertFalse(store.queueCleanupItem(entries[50]))
        XCTAssertEqual(store.cleanupQueue.count, CleanupQueue.limit)
    }

    @MainActor
    func testQueueChangesInvalidateOldConfirmationAndForgedReviewCannotAuthorize() throws {
        let entries = [item(0), item(1)]
        let store = try store(entries)
        XCTAssertTrue(store.queueCleanupItem(entries[0]))
        let old = try XCTUnwrap(store.prepareCleanupReview())
        XCTAssertTrue(store.queueCleanupItem(entries[1]))
        XCTAssertFalse(store.confirmCleanup(old))
        let current = try XCTUnwrap(store.prepareCleanupReview())
        let forged = CleanupReview(id: UUID(), scanRevision: current.scanRevision, items: current.items)
        XCTAssertFalse(store.confirmCleanup(forged))
        store.removeQueuedCleanupItem(entries[1].id)
        XCTAssertFalse(store.confirmCleanup(current))
        XCTAssertEqual(store.cleanupQueue, [entries[0]])
    }

    @MainActor
    func testNewScanAndScopeChoiceInvalidateSelectionAndReview() async throws {
        let entry = item(0)
        let store = try store([entry])
        XCTAssertTrue(store.queueCleanupItem(entry))
        let review = try XCTUnwrap(store.prepareCleanupReview())
        let token = try XCTUnwrap(store.beginFolderSelection())
        XCTAssertFalse(store.canConfirmCleanup(review))
        _ = store.completeFolderSelection(nil, revision: token)
        XCTAssertTrue(store.canConfirmCleanup(review), "Chooser Cancel leaves scope/results unchanged")
        store.scanDisk()
        XCTAssertFalse(store.confirmCleanup(review))
        XCTAssertTrue(store.cleanupQueue.isEmpty)
        await store.waitForDiskScan()
        XCTAssertNil(store.cleanupReview)
        XCTAssertTrue(store.scanFolder(URL(fileURLWithPath: "/fixture/selected")))
        await store.waitForDiskScan()
        store.diskCategories = [
            DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: entry.bytes, items: [entry])
        ]
        XCTAssertFalse(store.queueCleanupItem(entry))
        XCTAssertNil(store.prepareCleanupReview())
    }

    @MainActor
    func testPartialOrNeverCompletedScanCannotAuthorizeQueueOrLegacyTrash() async throws {
        let entry = item(0)
        let store = try store([entry])
        store.lastScanComplete = false
        XCTAssertFalse(store.queueCleanupItem(entry))
        XCTAssertFalse(store.deleteDiskItem(entry))
        let fixture = try SettingsPreferencesFixture()
        let partial = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            scanRunner: { update in
                update(
                    .init(
                        currentPath: "",
                        categories: [
                            DiskCategory(
                                id: "fixture", name: "Fixture", icon: "folder", bytes: entry.bytes, items: [entry])
                        ],
                        progress: 1, isComplete: true, skippedLocationCount: 1))
            },
            cleanupTrashClient: .init(move: { _ in
                XCTFail("Partial results must never move")
                return .movedToTrash
            }), cleanupEligibility: { _ in true })
        partial.scanDisk()
        await partial.waitForDiskScan()
        XCTAssertFalse(partial.queueCleanupItem(entry))
        XCTAssertNil(partial.prepareCleanupReview())
    }

    @MainActor
    func testSequentialBatchReportsPartialFailureAndNeverRetriesOrReplays() async throws {
        let entries = [item(0), item(1), item(2)]
        let recorder = CleanupClientRecorder()
        let store = try store(
            entries,
            client: .init(move: { entry in
                XCTAssertFalse(Thread.isMainThread)
                recorder.record(entry)
                return entry.id == entries[1].id ? .failed("Test refusal") : .movedToTrash
            }))
        for entry in entries { XCTAssertTrue(store.queueCleanupItem(entry)) }
        let review = try XCTUnwrap(store.prepareCleanupReview())
        XCTAssertTrue(store.confirmCleanup(review))
        XCTAssertFalse(store.confirmCleanup(review))
        XCTAssertFalse(store.queueCleanupItem(entries[1]))
        XCTAssertNil(store.beginFolderSelection())
        store.scanDisk()
        XCTAssertTrue(store.isPerformingCleanup)
        await store.waitForCleanup()
        XCTAssertEqual(recorder.items, entries)
        XCTAssertEqual(store.cleanupResults.map(\.outcome), [.movedToTrash, .failed("Test refusal"), .movedToTrash])
        XCTAssertEqual(store.cleanupQueue, [entries[1]])
        XCTAssertEqual(store.diskCategories.first?.items, [entries[1]])
        XCTAssertEqual(store.diskCategories.first?.bytes, entries[1].bytes)
        XCTAssertFalse(store.confirmCleanup(review))
        XCTAssertEqual(recorder.items.count, 3)
    }

    @MainActor
    func testStopAccountsForInFlightSuccessAndSkipsRemainingLocations() async throws {
        let entries = [item(0), item(1)]
        let gate = CleanupWorkerGate()
        defer { gate.release() }
        let recorder = CleanupClientRecorder()
        let store = try store(
            entries,
            client: .init(move: { entry in
                recorder.record(entry)
                gate.wait()
                return .movedToTrash
            }))
        for entry in entries { XCTAssertTrue(store.queueCleanupItem(entry)) }
        let review = try XCTUnwrap(store.prepareCleanupReview())
        XCTAssertTrue(store.confirmCleanup(review))
        await fulfillment(of: [gate.started], timeout: 2)
        store.stopCleanup()
        store.stopCleanup()
        XCTAssertTrue(store.isStoppingCleanup)
        gate.release()
        await store.waitForCleanup()
        XCTAssertEqual(recorder.items, [entries[0]])
        XCTAssertEqual(store.cleanupResults.map(\.outcome), [.movedToTrash, .notAttempted("Cleanup was stopped")])
        XCTAssertEqual(store.cleanupQueue, [entries[1]])
        XCTAssertFalse(store.isPerformingCleanup)
    }

    @MainActor
    func testShutdownSkipsRemainingItemsButDoesNotHideActualInFlightFailure() async throws {
        let entries = [item(0), item(1)]
        let gate = CleanupWorkerGate()
        defer { gate.release() }
        let store = try store(
            entries,
            client: .init(move: { _ in
                gate.wait()
                return .failed("Test failure")
            }))
        for entry in entries { XCTAssertTrue(store.queueCleanupItem(entry)) }
        XCTAssertTrue(store.confirmCleanup(try XCTUnwrap(store.prepareCleanupReview())))
        await fulfillment(of: [gate.started], timeout: 2)
        store.stopPolling()
        gate.release()
        await store.waitForCleanup()
        XCTAssertEqual(
            store.cleanupResults.map(\.outcome), [.failed("Test failure"), .notAttempted("Cleanup was stopped")])
        XCTAssertFalse(store.isPerformingCleanup)
        XCTAssertNil(store.toast, "Stopped store must not create a new toast timer")
        XCTAssertNil(store.prepareCleanupReview())
    }

    @MainActor
    func testAllEligibilityCheckedAgainBeforeCommit() throws {
        let entry = item(0)
        let fixture = try SettingsPreferencesFixture()
        var eligible = true
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            cleanupTrashClient: .init(move: { _ in
                XCTFail("Revoked eligibility must not move")
                return .movedToTrash
            }),
            cleanupEligibility: { _ in eligible })
        store.lastScanComplete = true
        store.diskCategories = [
            DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: entry.bytes, items: [entry])
        ]
        XCTAssertTrue(store.queueCleanupItem(entry))
        let review = try XCTUnwrap(store.prepareCleanupReview())
        eligible = false
        XCTAssertFalse(store.confirmCleanup(review))
        XCTAssertTrue(store.cleanupResults.isEmpty)
    }

    @MainActor
    func testNormalQuitDefersOnceUntilInFlightResultIsAccountedFor() async throws {
        let entries = [item(0), item(1)]
        let worker = CleanupWorkerGate()
        defer { worker.release() }
        let store = try store(
            entries,
            client: .init(move: { _ in
                worker.wait()
                return .movedToTrash
            }))
        for entry in entries { XCTAssertTrue(store.queueCleanupItem(entry)) }
        XCTAssertTrue(store.confirmCleanup(try XCTUnwrap(store.prepareCleanupReview())))
        await fulfillment(of: [worker.started], timeout: 2)
        let termination = CleanupTerminationGate()
        let ready = expectation(description: "Fake termination reply")
        var replies = 0
        XCTAssertTrue(
            termination.deferTerminationIfNeeded(store: store) {
                replies += 1
                ready.fulfill()
            })
        XCTAssertTrue(termination.deferTerminationIfNeeded(store: store) { XCTFail("Duplicate reply") })
        XCTAssertEqual(replies, 0)
        worker.release()
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(store.cleanupResults.map(\.outcome), [.movedToTrash, .notAttempted("Cleanup was stopped")])
        XCTAssertFalse(store.isPerformingCleanup)
    }

    @MainActor
    func testIdleQuitDoesNotCreateATaskOrChangeStore() throws {
        let store = try store([item(0)])
        let gate = CleanupTerminationGate()
        XCTAssertFalse(gate.deferTerminationIfNeeded(store: store) { XCTFail("No asynchronous reply when idle") })
        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(store.pollingState, .inactive)
    }

    @MainActor
    func testLaterItemEligibilityIsRecheckedAfterFirstMoveReturns() async throws {
        let entries = [item(0), item(1)]
        let fixture = try SettingsPreferencesFixture()
        let worker = CleanupWorkerGate()
        defer { worker.release() }
        var secondIsEligible = true
        let recorder = CleanupClientRecorder()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            cleanupTrashClient: .init(move: { item in
                recorder.record(item)
                worker.wait()
                return .movedToTrash
            }),
            cleanupEligibility: { $0.id != entries[1].id || secondIsEligible })
        store.lastScanComplete = true
        store.diskCategories = [
            DiskCategory(
                id: "fixture", name: "Fixture", icon: "folder", bytes: CleanupQueue.totalBytes(entries), items: entries)
        ]
        for entry in entries { XCTAssertTrue(store.queueCleanupItem(entry)) }
        XCTAssertTrue(store.confirmCleanup(try XCTUnwrap(store.prepareCleanupReview())))
        await fulfillment(of: [worker.started], timeout: 2)
        secondIsEligible = false
        worker.release()
        await store.waitForCleanup()
        XCTAssertEqual(recorder.items, [entries[0]])
        XCTAssertEqual(store.cleanupResults.last?.outcome, .notAttempted("Location changed or is no longer eligible"))
        XCTAssertEqual(store.cleanupQueue, [entries[1]])
    }

    @MainActor
    func testQueueReviewsAndResultsNeverPersistOrEnterDiagnostics() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            cleanupTrashClient: .init(move: { _ in .failed("Injected refusal") }), cleanupEligibility: { _ in true })
        let entry = item(420)
        store.lastScanComplete = true
        store.diskCategories = [
            DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: entry.bytes, items: [entry])
        ]
        let preferencesBefore = fixture.defaults.dictionaryRepresentation()
        XCTAssertTrue(store.queueCleanupItem(entry))
        XCTAssertTrue(store.confirmCleanup(try XCTUnwrap(store.prepareCleanupReview())))
        await store.waitForCleanup()
        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, preferencesBefore as NSDictionary)
        for format in [DiagnosticsFormat.json, .csv] {
            let text = try XCTUnwrap(
                String(
                    data: try DiagnosticsExport.encode(snapshot: store.diagnosticSnapshot(), format: format),
                    encoding: .utf8))
            for token in [entry.name, entry.path, "Injected refusal", "cleanupQueue"] {
                XCTAssertFalse(text.contains(token))
            }
        }
    }

    func testLogicalQueueTotalSaturatesInsteadOfOverflowing() {
        let item = DiskItem(
            id: "x", name: "x", path: "x", bytes: UInt64.max, fileCount: 0,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
        XCTAssertEqual(CleanupQueue.totalBytes([item, item]), UInt64.max)
    }
}
