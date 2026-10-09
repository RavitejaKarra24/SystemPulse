import Foundation
import XCTest

@testable import SystemPulse

final class VolumeMonitoringTests: XCTestCase {
    private let dataURL = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)

    func testStartupDataSurvivesHiddenFilteringAndReplacesSealedRoot() throws {
        let metadata: [VolumeSampler.Metadata] = [
            .init(mountURL: URL(fileURLWithPath: "/"), uuid: "SYSTEM", name: "Macintosh HD", isReadOnly: true),
            .init(mountURL: dataURL, uuid: "DATA", name: "Macintosh HD - Data", isHidden: true, isBrowsable: false),
            .init(mountURL: URL(fileURLWithPath: "/System/Volumes/Preboot"), name: "Preboot"),
            .init(mountURL: URL(fileURLWithPath: "/System/Volumes/VM"), name: "VM"),
            .init(mountURL: URL(fileURLWithPath: "/dev"), name: "devfs"),
            .init(mountURL: URL(fileURLWithPath: "/private/var/vm"), name: "Swap"),
        ]
        let result = VolumeSampler.sample(metadata: metadata, homeVolumeURL: dataURL)
        XCTAssertEqual(result.count, 1)
        let volume = try XCTUnwrap(result.first)
        XCTAssertEqual(volume.id, "uuid:data")
        XCTAssertTrue(volume.isHomeVolume)
        XCTAssertEqual(volume.mountURL, dataURL)
    }

    func testVisibleExternalReadOnlyAndUnknownMetadataArePreserved() throws {
        let result = VolumeSampler.sample(metadata: [
            .init(mountURL: url("Archive"), name: "Archive", isInternal: false, isReadOnly: true),
            .init(mountURL: url("Unknown")),
            // System-like display names are not proof that an external volume is a helper.
            .init(mountURL: url("Preboot"), name: "Preboot", isInternal: false),
            .init(mountURL: url("Hidden"), isHidden: true),
            .init(mountURL: url(".HiddenWithUnavailableMetadata")),
            .init(mountURL: url("Helper"), isBrowsable: false),
            .init(mountURL: URL(string: "https://example.com/volume")!),
        ])
        XCTAssertEqual(result.map(\.name), ["Archive", "Preboot", "Unknown"])
        let archive = try XCTUnwrap(result.first)
        XCTAssertEqual(archive.isInternal, false)
        XCTAssertTrue(archive.isReadOnly)
        let unknown = try XCTUnwrap(result.last)
        XCTAssertNil(unknown.isInternal)
        XCTAssertNil(unknown.totalBytes)
        XCTAssertNil(unknown.availableBytes)
        XCTAssertNil(unknown.usedBytes)
    }

    func testHiddenHomeVolumeIncludedAndActualHomeUUIDPreferred() throws {
        let result = VolumeSampler.sample(
            metadata: [
                .init(mountURL: dataURL, uuid: "DATA", isInternal: true),
                .init(mountURL: url("Home"), uuid: "HOME", isInternal: false, isHidden: true, isBrowsable: false),
            ], homeVolumeUUID: " home ")
        let home = try XCTUnwrap(VolumeSelection.resolve(selectedID: nil, in: result))
        XCTAssertEqual(home.id, "uuid:home")
        XCTAssertTrue(home.isHomeVolume)
    }

    func testUUIDIdentitySurvivesRenameAndRemountAndNormalizesCase() throws {
        let first = try XCTUnwrap(
            VolumeSampler.sample(metadata: [.init(mountURL: url("Old"), uuid: " ABC-123 ", name: "Old")]).first)
        let second = try XCTUnwrap(
            VolumeSampler.sample(metadata: [.init(mountURL: url("New"), uuid: "abc-123", name: "New")]).first)
        XCTAssertEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
    }

    func testDuplicateUUIDAndCanonicalMountPathsAreNormalizedWithoutAddingCapacity() {
        let metadata: [VolumeSampler.Metadata] = [
            .init(mountURL: url("Alias"), uuid: "DRIVE", name: "Alias"),
            .init(
                mountURL: url("Actual"), uuid: "drive", name: "Actual", isInternal: false,
                totalBytes: 100, importantAvailableBytes: 40),
            .init(mountURL: url("Actual/../Actual"), name: "Actual", totalBytes: 100),
        ]
        let result = VolumeSampler.sample(metadata: metadata)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "uuid:drive")
        XCTAssertEqual(result.first?.totalBytes, 100)
        XCTAssertEqual(result.first?.availableBytes, 40)
        XCTAssertEqual(result, VolumeSampler.sample(metadata: metadata.reversed()))
    }

    func testConflictingDuplicateMetadataHasDeterministicConservativeWinner() {
        let metadata: [VolumeSampler.Metadata] = [
            .init(mountURL: url("Disk"), uuid: "disk", isReadOnly: false, totalBytes: 100),
            .init(mountURL: url("Disk"), uuid: "disk", isReadOnly: true, totalBytes: 200),
        ]
        let result = VolumeSampler.sample(metadata: metadata)
        XCTAssertEqual(result, VolumeSampler.sample(metadata: metadata.reversed()))
        XCTAssertEqual(result.first?.isReadOnly, true)
        XCTAssertEqual(result.first?.totalBytes, 200)
    }

    func testMissingUUIDUsesCanonicalMountURLAndBlankNameFallsBackToMountName() throws {
        let result = VolumeSampler.sample(metadata: [
            .init(mountURL: url("Stable/../Stable"), uuid: "  ", name: " \n"),
            .init(mountURL: url("Stable")),
            .init(mountURL: URL(fileURLWithPath: "/Volumes/Stable", isDirectory: false)),
        ])
        let volume = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(volume.id, "mount:\(url("Stable").absoluteString)")
        XCTAssertEqual(volume.name, "Stable")
    }

    func testSharedCapacityDoesNotDeduplicateDistinctAPFSUserVolumes() {
        let result = VolumeSampler.sample(metadata: [
            .init(mountURL: url("Work"), uuid: "WORK", totalBytes: 1000, importantAvailableBytes: 600),
            .init(mountURL: url("Personal"), uuid: "PERSONAL", totalBytes: 1000, importantAvailableBytes: 600),
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.totalBytes), [1000, 1000])
        // No aggregate is computed: same container capacity must never be claimed additive.
    }

    func testImportantUsageCapacityTakesPrecedenceOverOrdinaryAvailability() throws {
        let volume = try XCTUnwrap(
            VolumeSampler.sample(metadata: [
                .init(mountURL: url("Disk"), totalBytes: 100, importantAvailableBytes: 60, ordinaryAvailableBytes: 20)
            ]).first)
        XCTAssertEqual(volume.availableBytes, 60)
        XCTAssertEqual(volume.usedBytes, 40)
        XCTAssertTrue(volume.availableForImportantUsage)
    }

    func testUnavailableImportantUsageFallsBackWithoutClaimingPurgeableCapacity() throws {
        let volume = try XCTUnwrap(
            VolumeSampler.sample(metadata: [
                .init(mountURL: url("Disk"), totalBytes: 100, importantAvailableBytes: -1, ordinaryAvailableBytes: 20)
            ]).first)
        XCTAssertEqual(volume.availableBytes, 20)
        XCTAssertEqual(volume.usedBytes, 80)
        XCTAssertFalse(volume.availableForImportantUsage)
    }

    func testNegativeAndMissingCapacitiesRemainUnavailableNotZero() throws {
        let volume = try XCTUnwrap(
            VolumeSampler.sample(metadata: [
                .init(mountURL: url("Disk"), totalBytes: -1, importantAvailableBytes: -1, ordinaryAvailableBytes: -1)
            ]).first)
        XCTAssertNil(volume.totalBytes)
        XCTAssertNil(volume.availableBytes)
        XCTAssertNil(volume.usedBytes)
        XCTAssertNil(makeVolume("A", total: nil, available: 10).usedBytes)
        XCTAssertNil(makeVolume("B", total: 10, available: nil).usedBytes)
    }

    func testUsedBytesClampsWhenAvailableExceedsTotalAndHandlesZeroAndUInt64Max() {
        XCTAssertEqual(makeVolume("A", total: 100, available: 110).usedBytes, 0)
        XCTAssertEqual(makeVolume("B", total: 0, available: 0).usedBytes, 0)
        XCTAssertEqual(makeVolume("C", total: .max, available: 0).usedBytes, .max)
        XCTAssertEqual(makeVolume("D", total: .max, available: .max).usedBytes, 0)
    }

    func testSortingAndDefaultSelectionAreIndependentOfEnumerationOrder() {
        let metadata: [VolumeSampler.Metadata] = [
            .init(mountURL: url("Z"), uuid: "z", name: "Z", isInternal: false),
            .init(mountURL: url("B"), uuid: "b", name: "B", isInternal: true),
            .init(mountURL: url("A"), uuid: "a", name: "A", isInternal: false),
        ]
        let result = VolumeSampler.sample(metadata: metadata)
        XCTAssertEqual(result.map(\.name), ["B", "A", "Z"])
        XCTAssertEqual(result, VolumeSampler.sample(metadata: metadata.reversed()))
        XCTAssertEqual(VolumeSelection.resolve(selectedID: nil, in: result)?.name, "B")
        XCTAssertEqual(VolumeSelection.resolve(selectedID: nil, in: result.reversed())?.name, "B")
    }

    func testExplicitSelectionWinsThenUnmountFallsBackToHomeWithoutMutatingID() {
        var home = makeVolume("Home")
        home.isHomeVolume = true
        let external = makeVolume("External")
        let selectedID: String? = external.id
        XCTAssertEqual(VolumeSelection.resolve(selectedID: selectedID, in: [home, external]), external)
        XCTAssertEqual(VolumeSelection.resolve(selectedID: selectedID, in: [home]), home)
        XCTAssertEqual(selectedID, external.id)
        XCTAssertNil(VolumeSelection.resolve(selectedID: selectedID, in: []))
        XCTAssertEqual(VolumeSelection.resolve(selectedID: selectedID, in: [home, external]), external)
    }

    func testHomeContainingMountUsesLongestComponentPrefixNotSimilarName() {
        let parent = makeVolume("Home")
        let nested = makeVolume("Home/Users")
        let similar = makeVolume("Home2")
        XCTAssertEqual(
            VolumeSelection.resolve(selectedID: nil, in: [similar, parent, nested], homeURL: url("Home/Users/alice")),
            nested)
        XCTAssertEqual(
            VolumeSelection.resolve(selectedID: nil, in: [parent, similar], homeURL: url("Home2/alice")), similar)
    }

    func testDefaultUsesStartupDataThenRootWhenHomeMetadataUnavailable() {
        let external = makeVolume("AAA")
        var data = makeVolume("Data")
        data = MonitoredVolume(
            id: data.id, name: data.name, mountURL: dataURL, isInternal: true, isReadOnly: false,
            totalBytes: nil, availableBytes: nil)
        let root = MonitoredVolume(
            id: "root", name: "Startup", mountURL: URL(fileURLWithPath: "/"), isInternal: true,
            isReadOnly: true, totalBytes: nil, availableBytes: nil)
        let home = URL(fileURLWithPath: "/Users/alice")
        XCTAssertEqual(VolumeSelection.resolve(selectedID: "removed", in: [external, root, data], homeURL: home), data)
        XCTAssertEqual(VolumeSelection.resolve(selectedID: nil, in: [external, root], homeURL: home), root)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true).standardizedFileURL
    }

    private func makeVolume(_ name: String, total: UInt64? = 100, available: UInt64? = 40) -> MonitoredVolume {
        MonitoredVolume(
            id: name, name: name, mountURL: url(name), isInternal: nil, isReadOnly: false,
            totalBytes: total, availableBytes: available)
    }
}
