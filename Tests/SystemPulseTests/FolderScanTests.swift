import Foundation
import XCTest

@testable import SystemPulse

final class FolderScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            "SystemPulseFolder-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testSmallFolderIncludesHiddenAndPackageFilesAndCannotAuthorizeTrash() throws {
        try Data(repeating: 0, count: 10).write(to: root.appendingPathComponent("small"))
        try Data(repeating: 0, count: 20).write(to: root.appendingPathComponent(".hidden"))
        let package = root.appendingPathComponent("Fixture.app/Contents")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 30).write(to: package.appendingPathComponent("payload"))
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(at: root) { recorder.append($0) }
        let final = try XCTUnwrap(recorder.updates.last)
        let item = try XCTUnwrap(final.categories.first?.items.first)
        XCTAssertTrue(final.isComplete)
        XCTAssertFalse(final.isCancelled)
        XCTAssertEqual(final.skippedLocationCount, 0)
        XCTAssertEqual(item.bytes, 60, "Folder inventory must not hide small files below the cleanup cutoff")
        XCTAssertEqual(item.fileCount, 3)
        XCTAssertFalse(item.safeToDelete)
        XCTAssertFalse(DiskScanner.canDelete(item, home: root.deletingLastPathComponent()))
    }

    func testEmptyFolderIsAnObservedZeroNotAnUnavailableRoot() throws {
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(at: root) { recorder.append($0) }
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertEqual(final.skippedLocationCount, 0)
        XCTAssertEqual(final.categories.first?.bytes, 0)
        XCTAssertEqual(final.categories.first?.items.first?.fileCount, 0)
    }

    func testChildSymlinkTargetsAreExcludedWithoutSuppressingSiblingFiles() throws {
        let outside = root.appendingPathComponent("Outside")
        let selected = root.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 9000).write(to: outside.appendingPathComponent("private"))
        try Data(repeating: 0, count: 100).write(to: selected.appendingPathComponent("included"))
        try FileManager.default.createSymbolicLink(
            at: selected.appendingPathComponent("link"), withDestinationURL: outside)
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(at: selected) { recorder.append($0) }
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertEqual(final.categories.first?.bytes, 100)
        XCTAssertEqual(final.skippedLocationCount, 0)
    }

    func testSymlinkRootAndAncestorAreRejectedWithoutMeasurement() throws {
        let actual = root.appendingPathComponent("Actual/Child")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 9000).write(to: actual.appendingPathComponent("private"))
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual.deletingLastPathComponent())
        for selected in [link, link.appendingPathComponent("Child")] {
            let recorder = ScanUpdateRecorder()
            DiskScanner.scanFolder(at: selected) { recorder.append($0) }
            let final = try XCTUnwrap(recorder.updates.last)
            XCTAssertTrue(final.categories.isEmpty)
            XCTAssertEqual(final.skippedLocationCount, 1)
        }
    }

    func testMissingFileRemoteAndFilesystemRootAreUnmeasuredNotFakeZeroes() throws {
        let file = root.appendingPathComponent("File")
        try Data([1]).write(to: file)
        for selected in [
            file, root.appendingPathComponent("Missing"), URL(fileURLWithPath: "/"),
            try XCTUnwrap(URL(string: "https://example.invalid/folder")),
        ] {
            let recorder = ScanUpdateRecorder()
            DiskScanner.scanFolder(at: selected) { recorder.append($0) }
            let final = try XCTUnwrap(recorder.updates.last)
            XCTAssertTrue(final.categories.isEmpty)
            XCTAssertEqual(final.skippedLocationCount, 1)
        }
    }

    func testRootDisappearingAfterValidationRemainsUnavailableNotEmpty() throws {
        let selected = root.appendingPathComponent("Disappearing")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(at: selected) { update in
            recorder.append(update)
            if !update.isComplete && update.currentPath == selected.path {
                // Removes only this test's empty fixture, never a user folder.
                do {
                    try FileManager.default.removeItem(at: selected)
                } catch {
                    XCTFail("Could not remove disposable fixture: \(error)")
                }
            }
        }
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertTrue(final.categories.isEmpty)
        XCTAssertGreaterThan(final.skippedLocationCount, 0)
    }

    func testExpectedRootCannotBeRetargetedThroughSymlink() throws {
        let outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 9000).write(to: outside.appendingPathComponent("private"))
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let result = DiskScanner.directorySize(
            at: link.path, expectedRoot: link, onFile: { _ in XCTFail("Must not enumerate redirected root") })
        XCTAssertEqual(result.bytes, 0)
        XCTAssertEqual(result.skippedLocationCount, 1)
    }

    func testFolderCancellationRetainsObservedReadOnlyProgress() throws {
        for index in 0..<160 {
            try Data(repeating: 0, count: 10).write(to: root.appendingPathComponent("file-\(index)"))
        }
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(
            at: root, isCancelled: { recorder.updates.contains { !$0.categories.isEmpty } },
            onUpdate: { recorder.append($0) })
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertTrue(final.isCancelled)
        XCTAssertGreaterThan(final.categories.first?.bytes ?? 0, 0)
        XCTAssertLessThan(final.categories.first?.bytes ?? 1600, 1600)
        XCTAssertFalse(try XCTUnwrap(final.categories.first?.items.first).safeToDelete)
    }

    @MainActor
    func testFolderScopeRejectsForgedSafeItemsAndRescansTheSameRoot() async throws {
        let fixture = try SettingsPreferencesFixture()
        let selected = root!
        let item = DiskItem(
            id: selected.path, name: "Forged safe", path: selected.path, bytes: 8192, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
        let category = DiskCategory(
            id: "selected-folder", name: "Selected folder", icon: "folder", bytes: 8192, items: [item])
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
                update(.init(currentPath: "", categories: [], progress: 1, isComplete: true))
            },
            folderScanRunner: { url, update in
                XCTAssertEqual(url, selected)
                XCTAssertFalse(Thread.isMainThread)
                let result = DiskScanner.ScanUpdate(
                    currentPath: "", categories: [category], progress: 1, isComplete: true)
                recorder.append(result)
                update(result)
            })
        XCTAssertTrue(store.scanFolder(selected))
        await store.waitForDiskScan()
        XCTAssertEqual(store.scanScope.folderURL, selected)
        XCTAssertTrue(store.cleanupIsBlocked)
        XCTAssertFalse(store.deleteDiskItem(item))
        XCTAssertEqual(trashCalls, 0)
        store.scanDisk()
        await store.waitForDiskScan()
        XCTAssertEqual(recorder.updates.count, 2)
        XCTAssertFalse(
            String(
                data: try DiagnosticsExport.encode(snapshot: store.diagnosticSnapshot(), format: .json), encoding: .utf8
            )?.contains(selected.lastPathComponent) == true)
        store.scanCleanupLocations()
        await store.waitForDiskScan()
        XCTAssertEqual(store.scanScope, .cleanupLocations)
        XCTAssertFalse(store.cleanupIsBlocked)
    }
}
