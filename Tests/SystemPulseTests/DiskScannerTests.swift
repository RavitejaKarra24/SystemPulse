import Foundation
import XCTest

@testable import SystemPulse

final class DiskScannerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemPulseTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Only removes fixtures created by this test, never user data or Trash.
        if let home { try FileManager.default.removeItem(at: home) }
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func item(_ url: URL, safe: Bool = true) -> DiskItem {
        DiskItem(
            id: url.path, name: "Fixture", path: url.path, bytes: 10, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: safe, safetyNote: "Fixture")
    }

    func testCacheDeletionCallsInjectedTrashOnlyAndPropagatesFailure() throws {
        let cache = try makeDirectory("Library/Caches/Fixture")
        var requests: [URL] = []
        XCTAssertTrue(DiskScanner.delete(item: item(cache), home: home) { requests.append($0) })
        XCTAssertEqual(requests, [cache])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(
            DiskScanner.delete(item: item(cache), home: home) { _ in throw CocoaError(.fileWriteNoPermission) })
    }

    func testStructuredTrashReportsPermissionDisappearanceAndGenericErrorsWithoutLeakingPaths() throws {
        let cache = try makeDirectory("Library/Caches/Fixture")
        let entry = item(cache)
        XCTAssertEqual(DiskScanner.moveToTrash(item: entry, home: home, trash: { _ in }), .movedToTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path), "Injected client must not move real files")
        let errors = [CocoaError(.fileWriteNoPermission), CocoaError(.fileNoSuchFile), CocoaError(.fileWriteUnknown)]
        for error in errors {
            let outcome = DiskScanner.moveToTrash(item: entry, home: home, trash: { _ in throw error })
            guard case .failed(let message) = outcome else { return XCTFail("Expected truthful failure") }
            XCTAssertFalse(message.contains(home.path))
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testStructuredTrashRefusesProtectedOrRedirectedLocationBeforeClientCall() throws {
        let target = try makeDirectory("Documents/Private")
        let caches = try makeDirectory("Library/Caches")
        let link = caches.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var calls = 0
        for entry in [item(target), item(link)] {
            let outcome = DiskScanner.moveToTrash(item: entry, home: home, trash: { _ in calls += 1 })
            guard case .failed = outcome else { return XCTFail("Expected protected refusal") }
        }
        XCTAssertEqual(calls, 0)
    }

    func testDeveloperCacheAllowlistIsExactNotAnAncestorOrDescendant() throws {
        let cache = try makeDirectory("Library/Developer/Xcode/DerivedData/Project")
        XCTAssertTrue(DiskScanner.canDelete(item(cache.deletingLastPathComponent()), home: home))
        XCTAssertFalse(DiskScanner.canDelete(item(cache), home: home))
        XCTAssertFalse(
            DiskScanner.canDelete(item(cache.deletingLastPathComponent().deletingLastPathComponent()), home: home))
    }

    func testUnsafeAndForgedSensitivePathsNeverReachTrash() throws {
        let paths = [
            "Library/Application Support/Fixture", "Library/Developer/CoreSimulator/Devices",
            "Library/Developer/Xcode/Archives", "Library/Containers/com.docker.docker",
            "Library/Saved Application State", ".Trash", ".npm", "Documents", "Library/Caches",
        ]
        var trashCalls = 0
        for path in paths {
            let url = try makeDirectory(path)
            // Even a forged safeToDelete label cannot authorize sensitive data.
            XCTAssertFalse(DiskScanner.delete(item: item(url), home: home) { _ in trashCalls += 1 }, path)
        }
        let cache = try makeDirectory("Library/Caches/Fixture")
        XCTAssertFalse(DiskScanner.delete(item: item(cache, safe: false), home: home) { _ in trashCalls += 1 })
        XCTAssertFalse(DiskScanner.delete(item: item(home), home: home) { _ in trashCalls += 1 })
        XCTAssertFalse(DiskScanner.delete(item: item(URL(fileURLWithPath: "/")), home: home) { _ in trashCalls += 1 })
        XCTAssertEqual(trashCalls, 0)
    }

    func testSymlinkRootAndSymlinkAncestorAreRejectedEvenInsideHome() throws {
        let target = try makeDirectory("Documents/Important")
        let caches = try makeDirectory("Library/Caches")
        let link = caches.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertFalse(DiskScanner.canDelete(item(link), home: home))
        let other = try makeDirectory("Other")
        try FileManager.default.createDirectory(
            at: other.appendingPathComponent("Caches/Fixture"), withIntermediateDirectories: true)
        let redirectedHome = try makeDirectory("RedirectedHome")
        try FileManager.default.createSymbolicLink(
            at: redirectedHome.appendingPathComponent("Library"), withDestinationURL: other)
        let indirect = redirectedHome.appendingPathComponent("Library/Caches/Fixture")
        XCTAssertFalse(DiskScanner.canDelete(item(indirect), home: redirectedHome))
    }

    func testRelativeTraversalAndMismatchedIdentityAreRejected() throws {
        let cache = try makeDirectory("Library/Caches/Fixture")
        for path in ["Library/Caches/Fixture", cache.path + "/..", cache.path + "/../Fixture", cache.path + "\0"] {
            let raw = DiskItem(
                id: path, name: "Fixture", path: path, bytes: 10, fileCount: 1,
                isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
            XCTAssertFalse(DiskScanner.canDelete(raw, home: home), path)
        }
        let mismatch = DiskItem(
            id: "other", name: "Fixture", path: cache.path, bytes: 10, fileCount: 1,
            isDirectory: true, categoryName: "Fixture", safeToDelete: true, safetyNote: "Fixture")
        XCTAssertFalse(DiskScanner.canDelete(mismatch, home: home))
    }

    func testMissingFileAndOutsideHomeAreRejected() throws {
        let missing = home.appendingPathComponent("Library/Caches/Missing")
        XCTAssertFalse(DiskScanner.canDelete(item(missing), home: home))
        let cache = try makeDirectory("Library/Caches/Fixture")
        let narrowHome = try makeDirectory("OtherHome")
        XCTAssertFalse(DiskScanner.canDelete(item(cache), home: narrowHome))
        try Data([1]).write(to: missing.deletingLastPathComponent().appendingPathComponent("File"))
        XCTAssertFalse(
            DiskScanner.canDelete(item(missing.deletingLastPathComponent().appendingPathComponent("File")), home: home))
    }

    func testDirectorySizeCancellationBeforeTraversalDoesNotReadFiles() throws {
        let root = try makeDirectory("Cancelled")
        try Data(repeating: 0, count: 8000).write(to: root.appendingPathComponent("payload"))
        let result = DiskScanner.directorySize(
            at: root.path, isCancelled: { true },
            onFile: { _ in
                XCTFail("Unexpected progress")
            })
        XCTAssertTrue(result.isCancelled)
        XCTAssertEqual(result.bytes, 0)
        XCTAssertEqual(result.fileCount, 0)
        XCTAssertEqual(result.skippedLocationCount, 0)
    }

    func testDirectorySizeStopsWithinTraversalAndKeepsOnlyObservedBytes() throws {
        let root = try makeDirectory("CancelledDuringTraversal")
        for index in 0..<160 {
            try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("file-\(index)"))
        }
        var cancelled = false
        let result = DiskScanner.directorySize(
            at: root.path, isCancelled: { cancelled }, onFile: { _ in cancelled = true })
        XCTAssertTrue(result.isCancelled)
        XCTAssertGreaterThan(result.fileCount, 0)
        XCTAssertLessThan(result.fileCount, 160)
        XCTAssertEqual(result.bytes, UInt64(result.fileCount) * 100)
    }

    func testMissingDirectoryIsReportedAsUnmeasuredNotCompleteZero() {
        let result = DiskScanner.directorySize(at: home.appendingPathComponent("Missing").path) { _ in }
        XCTAssertFalse(result.isCancelled)
        XCTAssertGreaterThan(result.skippedLocationCount, 0)
        XCTAssertEqual(result.bytes, 0)
    }

    func testScanOfDisposableHomeDoesNotTreatAbsentToolsAsFailures() throws {
        let root = try makeDirectory("Library/Caches/Fixture")
        try Data(repeating: 0, count: 8192).write(to: root.appendingPathComponent("payload"))
        let recorder = ScanUpdateRecorder()
        DiskScanner.scan(home: home) { recorder.append($0) }
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertTrue(final.isComplete)
        XCTAssertFalse(final.isCancelled)
        XCTAssertEqual(final.skippedLocationCount, 0)
        XCTAssertEqual(final.categories.flatMap(\.items).map(\.bytes), [8192])
    }

    func testScanRejectsRedirectedDiscoveryRootAndReportsPartialScope() throws {
        let target = try makeDirectory("Outside")
        try Data(repeating: 0, count: 8192).write(to: target.appendingPathComponent("private"))
        _ = try makeDirectory("Library")
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Library/Caches"), withDestinationURL: target)
        let recorder = ScanUpdateRecorder()
        DiskScanner.scan(home: home) { recorder.append($0) }
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertTrue(final.isComplete)
        XCTAssertGreaterThan(final.skippedLocationCount, 0)
        XCTAssertTrue(final.categories.isEmpty)
        XCTAssertFalse(recorder.updates.contains { $0.currentPath.hasPrefix(target.path) })
    }

    func testScanCancellationProducesStoppedTerminalStateNotCompletion() throws {
        let recorder = ScanUpdateRecorder()
        DiskScanner.scan(home: home, isCancelled: { true }, onUpdate: { recorder.append($0) })
        let final = try XCTUnwrap(recorder.updates.last)
        XCTAssertTrue(final.isComplete, "Terminal means worker finished, not a successful traversal")
        XCTAssertTrue(final.isCancelled)
        XCTAssertEqual(final.progress, 0)
        XCTAssertTrue(final.categories.isEmpty)
    }

    func testDirectorySizeIncludesHiddenAndPackageFilesButNotSymlinkTargets() throws {
        let root = try makeDirectory("Measured")
        try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("visible"))
        try Data(repeating: 0, count: 200).write(to: root.appendingPathComponent(".hidden"))
        let package = try makeDirectory("Measured/Fixture.app/Contents")
        try Data(repeating: 0, count: 300).write(to: package.appendingPathComponent("payload"))
        let outside = try makeDirectory("Outside")
        try Data(repeating: 0, count: 1000).write(to: outside.appendingPathComponent("excluded"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        let result = DiskScanner.directorySize(at: root.path) { _ in }
        XCTAssertEqual(result.bytes, 600)
        XCTAssertEqual(result.fileCount, 3)
    }
}
