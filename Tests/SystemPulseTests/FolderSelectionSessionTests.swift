import Foundation
import XCTest

@testable import SystemPulse

@MainActor
private final class FolderPanelMock {
    var pending: ((URL?) -> Void)?
    var begins = 0
    var cancellations = 0
    var client: FolderSelectionClient {
        FolderSelectionClient(
            begin: { [self] completion in
                begins += 1
                pending = completion
            }, cancel: { [self] in cancellations += 1 })
    }
    func takeCompletion() throws -> (URL?) -> Void {
        defer { pending = nil }
        return try XCTUnwrap(pending)
    }
    func respond(_ url: URL?) throws { try takeCompletion()(url) }
}

private final class FolderSelectionWeakStoreReference {
    weak var value: MonitorStore?
    init(_ value: MonitorStore?) { self.value = value }
}

final class FolderSelectionSessionTests: XCTestCase {
    @MainActor
    func testOnlyOneChooserAndCancellationPreservesResultsAndScope() async throws {
        let fixture = try SettingsPreferencesFixture()
        let recorder = ScanUpdateRecorder()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            scanRunner: { _ in recorder.append(.init(currentPath: "", categories: [], progress: 1, isComplete: true)) })
        store.lastScanComplete = true
        store.scanProgress = 1
        let mock = FolderPanelMock()
        let session = FolderSelectionSession(client: mock.client)
        session.present(for: store)
        session.present(for: store)
        store.scanDisk()
        XCTAssertEqual(mock.begins, 1)
        XCTAssertTrue(store.isChoosingScanFolder)
        XCTAssertTrue(store.cleanupIsBlocked)
        XCTAssertTrue(recorder.updates.isEmpty)
        try mock.respond(nil)
        XCTAssertFalse(session.isPresenting)
        XCTAssertFalse(store.isChoosingScanFolder)
        XCTAssertFalse(store.cleanupIsBlocked)
        XCTAssertEqual(store.scanScope, .cleanupLocations)
        XCTAssertTrue(store.lastScanComplete)
        XCTAssertEqual(store.scanProgress, 1)
    }

    @MainActor
    func testAcceptedFolderStartsOneReadOnlyWorkerWithoutPersistingPath() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let before = fixture.defaults.dictionaryRepresentation()
        let selected = URL(fileURLWithPath: "/fixture/private-folder")
        let recorder = ScanUpdateRecorder()
        let store = MonitorStore(
            startPolling: false, preferences: preferences,
            folderScanRunner: { url, update in
                XCTAssertEqual(url, selected)
                let result = DiskScanner.ScanUpdate(currentPath: "", categories: [], progress: 1, isComplete: true)
                recorder.append(result)
                update(result)
            })
        let mock = FolderPanelMock()
        let session = FolderSelectionSession(client: mock.client)
        session.present(for: store)
        try mock.respond(selected)
        await store.waitForDiskScan()
        XCTAssertEqual(recorder.updates.count, 1)
        XCTAssertTrue(store.scanScope.isReadOnly)
        XCTAssertFalse(store.isChoosingScanFolder)
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: fixture.defaults.dictionaryRepresentation()))
    }

    @MainActor
    func testCancelledOldResponseCannotApplyDuringANewChooser() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            folderScanRunner: { _, _ in XCTFail("Cancelled response must not scan") })
        let mock = FolderPanelMock()
        let session = FolderSelectionSession(client: mock.client)
        session.present(for: store)
        let staleResponse = try mock.takeCompletion()
        session.cancel()
        XCTAssertEqual(mock.cancellations, 1)
        session.present(for: store)
        staleResponse(URL(fileURLWithPath: "/fixture/stale"))
        XCTAssertTrue(session.isPresenting)
        XCTAssertTrue(store.isChoosingScanFolder)
        XCTAssertEqual(store.scanScope, .cleanupLocations)
        try mock.respond(nil)
    }

    @MainActor
    func testShutdownRejectsAcceptedDelayedResponse() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            folderScanRunner: { _, _ in XCTFail("Shutdown must not scan") })
        let mock = FolderPanelMock()
        let session = FolderSelectionSession(client: mock.client)
        session.present(for: store)
        store.stopPolling()
        try mock.respond(URL(fileURLWithPath: "/fixture/late"))
        XCTAssertFalse(store.isChoosingScanFolder)
        XCTAssertFalse(store.isScanning)
        XCTAssertEqual(store.scanScope, .cleanupLocations)
    }

    @MainActor
    func testActiveScanCannotOpenChooser() throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        store.isScanning = true  // Fixture only; no filesystem worker.
        let mock = FolderPanelMock()
        let session = FolderSelectionSession(client: mock.client)
        session.present(for: store)
        XCTAssertEqual(mock.begins, 0)
        XCTAssertFalse(session.isPresenting)
        XCTAssertFalse(store.isChoosingScanFolder)
    }

    @MainActor
    func testPendingChooserDoesNotRetainDiscardedStore() throws {
        let fixture = try SettingsPreferencesFixture()
        var store: MonitorStore? = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            folderScanRunner: { _, _ in XCTFail("Discarded store must not scan") })
        let reference = FolderSelectionWeakStoreReference(store)
        let mock = FolderPanelMock()
        let session = FolderSelectionSession(client: mock.client)
        session.present(for: try XCTUnwrap(store))
        store = nil
        XCTAssertNil(reference.value)
        try mock.respond(URL(fileURLWithPath: "/fixture/late"))
        XCTAssertFalse(session.isPresenting)
    }

    @MainActor
    func testInvalidURLDoesNotReplaceScopeOrStartWorker() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            folderScanRunner: { _, _ in XCTFail("Invalid URLs must not scan") })
        for invalid in [
            URL(fileURLWithPath: "/"), try XCTUnwrap(URL(string: "https://example.invalid/folder")),
            try XCTUnwrap(URL(string: "file://example.invalid/folder")),
        ] {
            let token = try XCTUnwrap(store.beginFolderSelection())
            XCTAssertFalse(store.completeFolderSelection(invalid, revision: token))
            XCTAssertEqual(store.scanScope, .cleanupLocations)
            XCTAssertFalse(store.isScanning)
            XCTAssertFalse(store.isChoosingScanFolder)
        }
    }
}
