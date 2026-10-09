import Foundation
import XCTest

@testable import SystemPulse

/// Test-only shorthand: production call sites must keep the authorization minted
/// when the user opened the confirmation, not prepare it when confirming.
extension MonitorStore {
    @MainActor
    @discardableResult
    func deleteDiskItem(_ item: DiskItem) -> Bool {
        guard let review = prepareDiskTrashReview(item) else { return false }
        return deleteDiskItem(review)
    }
}

final class SingleItemTrashTests: XCTestCase {
    @MainActor
    func testConfirmationCannotDeleteIdenticalPathFromANewScan() async throws {
        let fixture = try SettingsPreferencesFixture()
        let item = DiskItem(
            id: "/fixture/cache", name: "Cache", path: "/fixture/cache", bytes: 100, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
        let category = DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: 100, items: [item])
        var calls = 0
        let store = MonitorStore(
            startPolling: false,
            trashItem: { _ in
                calls += 1
                return true
            }, preferences: fixture.makePreferences(),
            scanRunner: { update in
                update(.init(currentPath: "", categories: [category], progress: 1, isComplete: true))
            })
        store.scanDisk()
        await store.waitForDiskScan()
        let old = try XCTUnwrap(store.prepareDiskTrashReview(item))
        store.scanDisk()
        await store.waitForDiskScan()
        XCTAssertFalse(store.deleteDiskItem(old))
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(store.deleteDiskItem(try XCTUnwrap(store.prepareDiskTrashReview(item))))
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testOpeningSingleOrBatchReviewRevokesTheOtherAuthorization() throws {
        let fixture = try SettingsPreferencesFixture()
        let item = DiskItem(
            id: "/fixture/cache", name: "Cache", path: "/fixture/cache", bytes: 100, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
        let store = MonitorStore(
            startPolling: false,
            trashItem: { _ in
                XCTFail("Expired single review")
                return false
            },
            preferences: fixture.makePreferences(),
            cleanupTrashClient: .init(move: { _ in
                XCTFail("Expired batch review")
                return .movedToTrash
            }),
            cleanupEligibility: { _ in true })
        store.lastScanComplete = true
        store.diskCategories = [DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: 100, items: [item])]
        XCTAssertTrue(store.queueCleanupItem(item))
        let batch = try XCTUnwrap(store.prepareCleanupReview())
        let single = try XCTUnwrap(store.prepareDiskTrashReview(item))
        XCTAssertFalse(store.confirmCleanup(batch))
        XCTAssertNotNil(store.prepareCleanupReview())
        XCTAssertFalse(store.deleteDiskItem(single))
    }

    @MainActor
    func testFailedSingleConfirmationIsOneShotAndForgedTokenRefused() throws {
        let fixture = try SettingsPreferencesFixture()
        let item = DiskItem(
            id: "/fixture/cache", name: "Cache", path: "/fixture/cache", bytes: 100, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
        var calls = 0
        let store = MonitorStore(
            startPolling: false,
            trashItem: { _ in
                calls += 1
                return false
            }, preferences: fixture.makePreferences())
        store.lastScanComplete = true
        store.diskCategories = [DiskCategory(id: "fixture", name: "Fixture", icon: "folder", bytes: 100, items: [item])]
        let review = try XCTUnwrap(store.prepareDiskTrashReview(item))
        let forged = DiskTrashReview(id: UUID(), scanRevision: review.scanRevision, item: item)
        XCTAssertFalse(store.deleteDiskItem(forged))
        XCTAssertFalse(store.deleteDiskItem(review))
        XCTAssertFalse(store.deleteDiskItem(review))
        XCTAssertEqual(calls, 1)
    }
}
