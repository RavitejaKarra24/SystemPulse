import Foundation
import XCTest

@testable import SystemPulse

final class FolderInventoryTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/fixture/root")

    func testLargestFilesAreBoundedGlobalAndDeterministicOnTies() {
        var accumulator = FolderInventoryAccumulator(root: root)
        for index in 0..<250 {
            accumulator.record(
                url: root.appendingPathComponent("file-\(index)"), isDirectory: false,
                logicalBytes: UInt64(index), allocatedBytes: nil)
        }
        let snapshot = accumulator.snapshot
        XCTAssertEqual(snapshot.observedFileCount, 250)
        XCTAssertEqual(snapshot.largestFiles.count, 100)
        XCTAssertEqual(snapshot.largestFiles.first?.logicalBytes, 249)
        XCTAssertEqual(snapshot.largestFiles.last?.logicalBytes, 150)
        XCTAssertTrue(snapshot.directories.isEmpty)
        var tied = FolderInventoryAccumulator(root: root)
        for name in ["z", "a", "b"] {
            tied.record(url: root.appendingPathComponent(name), isDirectory: false, logicalBytes: 10, allocatedBytes: 0)
        }
        XCTAssertEqual(tied.snapshot.largestFiles.map(\.name), ["a", "b", "z"])
        XCTAssertEqual(tied.snapshot.largestFiles.first?.allocatedBytes, 0, "Observed allocation zero is not missing")
    }

    func testImmediateFolderCapIsDisclosedButAllFilesStillCompeteForTopList() {
        var accumulator = FolderInventoryAccumulator(root: root)
        for index in 0..<300 {
            let child = root.appendingPathComponent("Folder-\(index)", isDirectory: true)
            accumulator.record(url: child, isDirectory: true, logicalBytes: 0, allocatedBytes: nil)
            accumulator.record(
                url: child.appendingPathComponent("file"), isDirectory: false,
                logicalBytes: UInt64(index), allocatedBytes: nil)
        }
        let snapshot = accumulator.snapshot
        XCTAssertEqual(snapshot.directories.count, 256)
        XCTAssertEqual(snapshot.omittedDirectoryCount, 44)
        XCTAssertEqual(snapshot.largestFiles.first?.logicalBytes, 299)
        XCTAssertEqual(snapshot.observedFileCount, 300)
        XCTAssertNil(snapshot.directories.first?.allocatedBytes, "Do not invent directory allocation")
    }

    func testDirectorySummaryIncludesAllNestedObservedBytesWithoutRetainingTree() {
        var accumulator = FolderInventoryAccumulator(root: root)
        let child = root.appendingPathComponent("Child")
        accumulator.record(url: child, isDirectory: true, logicalBytes: 0, allocatedBytes: nil)
        accumulator.record(
            url: child.appendingPathComponent("Nested"), isDirectory: true, logicalBytes: 0, allocatedBytes: nil)
        for index in 0..<200 {
            accumulator.record(
                url: child.appendingPathComponent("Nested/file-\(index)"), isDirectory: false,
                logicalBytes: 10, allocatedBytes: 16)
        }
        let snapshot = accumulator.snapshot
        XCTAssertEqual(snapshot.directories.count, 1)
        XCTAssertEqual(snapshot.directories.first?.logicalBytes, 2000)
        XCTAssertEqual(snapshot.directories.first?.fileCount, 200)
        XCTAssertEqual(snapshot.largestFiles.count, 100)
    }

    func testScopeBoundaryDoesNotAcceptSiblingWithSimilarPrefix() {
        var accumulator = FolderInventoryAccumulator(root: root)
        accumulator.record(
            url: URL(fileURLWithPath: "/fixture/root-other/private"), isDirectory: false,
            logicalBytes: 100, allocatedBytes: 100)
        accumulator.record(url: root, isDirectory: true, logicalBytes: 0, allocatedBytes: nil)
        XCTAssertTrue(accumulator.snapshot.rows().isEmpty)
        XCTAssertEqual(accumulator.snapshot.observedFileCount, 0)
    }

    func testSearchMatchesOnlyRetainedRowsAndFiltersType() {
        var accumulator = FolderInventoryAccumulator(root: root)
        let child = root.appendingPathComponent("Projects")
        accumulator.record(url: child, isDirectory: true, logicalBytes: 0, allocatedBytes: nil)
        accumulator.record(
            url: child.appendingPathComponent("Readme.MD"), isDirectory: false,
            logicalBytes: 100, allocatedBytes: nil)
        let inventory = accumulator.snapshot
        XCTAssertEqual(inventory.rows(search: "PROJECTS readme", filter: .files).count, 1)
        XCTAssertEqual(inventory.rows(filter: .folders).count, 1)
        XCTAssertTrue(inventory.rows(search: "missing").isEmpty)
        XCTAssertEqual(inventory.rows(search: "  ").count, 2)
    }

    func testDirectoryTotalsCannotOverflow() {
        var accumulator = FolderInventoryAccumulator(root: root)
        let child = root.appendingPathComponent("Child")
        accumulator.record(url: child, isDirectory: true, logicalBytes: 0, allocatedBytes: nil)
        accumulator.record(
            url: child.appendingPathComponent("a"), isDirectory: false, logicalBytes: UInt64.max, allocatedBytes: nil)
        accumulator.record(
            url: child.appendingPathComponent("b"), isDirectory: false, logicalBytes: 1, allocatedBytes: nil)
        XCTAssertEqual(accumulator.snapshot.directories.first?.logicalBytes, UInt64.max)
    }
}

final class FolderInventoryIntegrationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            "SystemPulseInventory-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    private func writeFixture() throws -> URL {
        let child = root.appendingPathComponent("Child/Nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 50).write(to: root.appendingPathComponent(".hidden"))
        try Data(repeating: 0, count: 200).write(to: child.appendingPathComponent("Large"))
        return child.deletingLastPathComponent()
    }

    func testLiveDisposableScanBuildsLargestFilesAndImmediateSummariesInOneTraversal() throws {
        _ = try writeFixture()
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(at: root) { recorder.append($0) }
        let final = try XCTUnwrap(recorder.updates.last)
        let inventory = try XCTUnwrap(final.inventory)
        XCTAssertEqual(final.categories.first?.bytes, 250)
        XCTAssertEqual(inventory.observedFileCount, 2)
        XCTAssertEqual(inventory.largestFiles.map(\.logicalBytes), [200, 50])
        XCTAssertEqual(inventory.directories.map(\.logicalBytes), [200])
        XCTAssertEqual(inventory.directories.map(\.fileCount), [1])
        XCTAssertEqual(inventory.largestFiles.first?.name, "Large")
        // Hardware/filesystem allocation is optional; if available it is nonnegative.
        XCTAssertEqual(inventory.largestFiles.count, 2)
    }

    func testValidatedActionRejectsForgedRemovedAndRedirectedEntries() throws {
        let child = try writeFixture()
        let recorder = ScanUpdateRecorder()
        DiskScanner.scanFolder(at: root) { recorder.append($0) }
        let inventory = try XCTUnwrap(recorder.updates.last?.inventory)
        let file = try XCTUnwrap(inventory.largestFiles.first)
        XCTAssertEqual(FolderInventoryAccess.validatedURL(for: file, in: inventory), file.url)
        var forged = file
        forged.logicalBytes += 1
        XCTAssertNil(FolderInventoryAccess.validatedURL(for: forged, in: inventory))
        try FileManager.default.removeItem(at: file.url)
        XCTAssertNil(FolderInventoryAccess.validatedURL(for: file, in: inventory))
        let outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: child)
        try FileManager.default.createSymbolicLink(at: child, withDestinationURL: outside)
        let directory = try XCTUnwrap(inventory.directories.first)
        XCTAssertNil(FolderInventoryAccess.validatedURL(for: directory, in: inventory))
    }

    @MainActor
    func testDrillDownBackAndScopeResetAreExplicitReadOnlyScans() async throws {
        _ = try writeFixture()
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            scanRunner: { update in
                update(.init(currentPath: "", categories: [], progress: 1, isComplete: true))
            })
        XCTAssertTrue(store.scanFolder(root))
        await store.waitForDiskScan()
        let rootInventory = try XCTUnwrap(store.folderInventory)
        let child = try XCTUnwrap(rootInventory.directories.first)
        XCTAssertTrue(store.drillIntoFolder(child))
        XCTAssertNil(store.inventoryActionURL(for: child), "No stale preview while new worker runs")
        await store.waitForDiskScan()
        XCTAssertEqual(store.scanScope.folderURL, child.url)
        XCTAssertEqual(store.folderNavigation.count, 2)
        XCTAssertTrue(store.cleanupIsBlocked)
        XCTAssertFalse(store.drillIntoFolder(child), "An old-scope entry is not a navigation authority")
        XCTAssertTrue(store.backToParentFolder())
        await store.waitForDiskScan()
        XCTAssertEqual(store.scanScope.folderURL?.path, root.standardizedFileURL.path)
        XCTAssertEqual(store.folderNavigation.count, 1)
        XCTAssertFalse(store.backToParentFolder(), "Cannot climb outside selected root")
        let current = try XCTUnwrap(store.folderInventory?.largestFiles.first)
        XCTAssertNotNil(store.inventoryActionURL(for: current))
        let token = try XCTUnwrap(store.beginFolderSelection())
        XCTAssertNil(store.inventoryActionURL(for: current))
        _ = store.completeFolderSelection(nil, revision: token)
        XCTAssertNotNil(store.inventoryActionURL(for: current))
        store.scanCleanupLocations()
        await store.waitForDiskScan()
        XCTAssertNil(store.folderInventory)
        XCTAssertTrue(store.folderNavigation.isEmpty)
        XCTAssertNil(store.inventoryActionURL(for: current))
    }

    @MainActor
    func testNavigationHistoryHasHardLimitAndCannotClimbOutsideRoot() async throws {
        let selected = root!
        var directory = selected
        for _ in 0..<64 {
            directory.appendPathComponent("Child", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            folderScanRunner: { url, update in
                let child = FolderInventoryEntry(
                    url: url.appendingPathComponent("Child", isDirectory: true), isDirectory: true,
                    logicalBytes: 0, allocatedBytes: nil, fileCount: 0)
                let inventory = FolderInventory(root: url, directories: [child])
                update(.init(currentPath: "", categories: [], progress: 1, isComplete: true, inventory: inventory))
            })
        XCTAssertTrue(store.scanFolder(selected))
        await store.waitForDiskScan()
        for _ in 0..<63 {
            XCTAssertTrue(store.drillIntoFolder(try XCTUnwrap(store.folderInventory?.directories.first)))
            await store.waitForDiskScan()
        }
        XCTAssertEqual(store.folderNavigation.count, 64)
        XCTAssertFalse(store.drillIntoFolder(try XCTUnwrap(store.folderInventory?.directories.first)))
        XCTAssertEqual(store.folderNavigation.count, 64)
    }

    @MainActor
    func testInventoryPathsAndNamesNeverEnterDiagnostics() async throws {
        _ = try writeFixture()
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        XCTAssertTrue(store.scanFolder(root))
        await store.waitForDiskScan()
        XCTAssertNotNil(store.folderInventory)
        for format in [DiagnosticsFormat.json, .csv] {
            let text = try XCTUnwrap(
                String(
                    data: try DiagnosticsExport.encode(snapshot: store.diagnosticSnapshot(), format: format),
                    encoding: .utf8))
            for privateToken in [root.lastPathComponent, "Nested", "Large", ".hidden"] {
                XCTAssertFalse(text.contains(privateToken))
            }
        }
    }

    @MainActor
    func testShutdownBlocksPreviewAndDrillNavigation() async throws {
        _ = try writeFixture()
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        XCTAssertTrue(store.scanFolder(root))
        await store.waitForDiskScan()
        let entry = try XCTUnwrap(store.folderInventory?.directories.first)
        store.stopPolling()
        XCTAssertNil(store.inventoryActionURL(for: entry))
        XCTAssertFalse(store.drillIntoFolder(entry))
        XCTAssertFalse(store.backToParentFolder())
    }
}
