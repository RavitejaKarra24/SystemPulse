import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import SystemPulse

final class MetricHistoryTests: XCTestCase {
    private let origin = Date(timeIntervalSinceReferenceDate: 0)

    private func date(_ seconds: TimeInterval) -> Date {
        origin.addingTimeInterval(seconds)
    }

    @MainActor
    func testLegacyAndTimedGraphAPIsRenderInBothAppearances() async throws {
        // Rendering checks use an empty timed history; model/geometry tests below have fixed time.
        // This also locks down the synthesized initializer's trailing parameter order.
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack {
                GraphCard(
                    history: [1, 2, 3], metric: .cpu, formatter: { "\($0)%" },
                    secondaryHistory: [3, 2, 1], secondaryColor: .orange,
                    title: "Legacy", primaryLabel: "Primary", secondaryLabel: "Secondary")
                GraphCard(
                    history: [], metric: .network, formatter: { "\($0) B/s" },
                    secondaryColor: .orange, title: "Timed", primaryLabel: "Download", secondaryLabel: "Upload",
                    timedHistory: MetricHistory(), secondaryTimedHistory: MetricHistory())
            }
            .frame(width: 380)
            .environment(\.colorScheme, scheme)
            let hosting = NSHostingView(rootView: view)
            let frame = NSRect(x: 0, y: 0, width: 380, height: 700)
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

    func testRangeContractAndSampleIdentityCoding() throws {
        XCTAssertEqual(HistoryRange.allCases.map(\.label), ["5m", "1h", "24h"])
        XCTAssertEqual(HistoryRange.allCases.map(\.duration), [300, 3_600, 86_400])
        XCTAssertEqual(HistoryRange.allCases.map(\.id), HistoryRange.allCases)
        let sample = TimedMetricSample(timestamp: date(1.25), value: 2_048)
        XCTAssertEqual(sample.id, date(1.25))
        XCTAssertEqual(TimedMetricSample(timestamp: sample.timestamp, value: 99).id, sample.id)
        XCTAssertEqual(try JSONDecoder().decode(TimedMetricSample.self, from: JSONEncoder().encode(sample)), sample)
    }

    func testEmptyHistoryAndEmptyWindows() {
        let history = MetricHistory()
        XCTAssertNil(history.latestTimestamp)
        for range in HistoryRange.allCases {
            XCTAssertTrue(history.points(in: range, endingAt: origin).isEmpty)
        }
        XCTAssertNil(MetricHistoryWindow(history: history, range: .oneHour, endingAt: origin).nearestSample(to: 0.5))
    }

    func testRawWindowIsInclusiveAndPreservesValuesAndSubsecondTimestamps() {
        var history = MetricHistory()
        for (time, value) in [(0.0, 1.0), (0.25, 2.0), (299.75, 3.0), (300.0, 4.0)] {
            history.record(value, at: date(time))
        }
        let points = history.points(in: .fiveMinutes, endingAt: date(300))
        XCTAssertEqual(points.map(\.timestamp), [date(0), date(0.25), date(299.75), date(300)])
        XCTAssertEqual(points.map(\.value), [1, 2, 3, 4])
        XCTAssertEqual(history.latestTimestamp, date(300))
        history.record(5, at: date(300.25))
        XCTAssertEqual(
            history.points(in: .fiveMinutes, endingAt: date(300.25)).map(\.timestamp),
            [date(0.25), date(299.75), date(300), date(300.25)])
        XCTAssertEqual(history.rawSampleCount, 4)
    }

    func testTenSecondBucketsAreSampleMeansAtLastActualTimestamp() {
        var history = MetricHistory()
        history.record(10, at: date(0.5))
        history.record(20, at: date(2))
        history.record(60, at: date(9.5))
        history.record(80, at: date(10))
        history.record(100, at: date(17))
        let points = history.points(in: .oneHour, endingAt: date(20))
        XCTAssertEqual(points.map(\.timestamp), [date(9.5), date(17)])
        XCTAssertEqual(points.map(\.value), [30, 90])
        XCTAssertEqual(history.points(in: .fiveMinutes, endingAt: date(20)).count, 5)
    }

    func testMinuteMeansIncludeEveryRawSampleNotMeansOfTenSecondMeans() {
        var history = MetricHistory()
        history.record(0, at: date(1))
        history.record(0, at: date(2))
        history.record(90, at: date(11))
        history.record(60, at: date(60))
        let points = history.points(in: .oneDay, endingAt: date(61))
        XCTAssertEqual(points.map(\.timestamp), [date(11), date(60)])
        XCTAssertEqual(points.map(\.value), [30, 60])
    }

    func testAggregationDoesNotOverflowForFiniteLargeValues() {
        var history = MetricHistory()
        history.record(Double.greatestFiniteMagnitude, at: date(0))
        history.record(Double.greatestFiniteMagnitude, at: date(1))
        history.record(0, at: date(2))
        let mean = history.points(in: .oneDay, endingAt: date(3)).first?.value
        XCTAssertNotNil(mean)
        XCTAssertTrue(mean?.isFinite == true)
        XCTAssertEqual((mean ?? 0) / Double.greatestFiniteMagnitude, 2.0 / 3.0, accuracy: 1e-12)
    }

    func testRejectsInvalidValuesDatesDuplicatesAndOutOfOrderWithoutAdvancingClock() {
        var history = MetricHistory()
        for value in [Double.nan, .infinity, -.infinity, -1] {
            history.record(value, at: date(100))
        }
        history.record(2, at: Date(timeIntervalSinceReferenceDate: .nan))
        history.record(2, at: Date(timeIntervalSinceReferenceDate: .infinity))
        XCTAssertNil(history.latestTimestamp)
        history.record(5, at: date(10))
        history.record(99, at: date(9))
        history.record(99, at: date(10))
        history.record(.nan, at: date(1_000_000))
        history.record(0, at: date(11))
        XCTAssertEqual(history.latestTimestamp, date(11))
        XCTAssertEqual(history.points(in: .fiveMinutes, endingAt: date(11)).map(\.value), [5, 0])
        XCTAssertEqual(history.hourBucketCount, 1)
        for range in HistoryRange.allCases {
            XCTAssertTrue(history.points(in: range, endingAt: Date(timeIntervalSinceReferenceDate: .nan)).isEmpty)
        }
    }

    func testCoarseBucketsCrossingQueryEdgesAreOmittedNotContaminated() {
        var history = MetricHistory()
        history.record(1, at: date(0))
        history.record(3, at: date(9))
        history.record(5, at: date(11))
        // Start is 5: first bucket includes an out-of-window observation at 0.
        XCTAssertEqual(history.points(in: .oneHour, endingAt: date(3_605)).map(\.timestamp), [date(11)])
        // End is 5: first bucket includes a future observation at 9. No partial mean is invented.
        XCTAssertTrue(history.points(in: .oneHour, endingAt: date(5)).isEmpty)
        XCTAssertEqual(history.points(in: .fiveMinutes, endingAt: date(5)).map(\.value), [1])
        XCTAssertTrue(history.points(in: .oneDay, endingAt: date(5)).isEmpty)
        XCTAssertTrue(history.points(in: .oneDay, endingAt: date(86_405)).isEmpty)
    }

    func testGapsCreateNoEmptyBucketsNoZeroFillAndNoInterpolation() {
        var history = MetricHistory()
        history.record(7, at: date(1))
        history.record(9, at: date(121))
        for range in HistoryRange.allCases {
            let points = history.points(in: range, endingAt: date(122))
            XCTAssertEqual(points.map(\.timestamp), [date(1), date(121)])
            XCTAssertEqual(points.map(\.value), [7, 9])
        }
        XCTAssertTrue(history.points(in: .fiveMinutes, endingAt: date(500)).isEmpty)
        XCTAssertEqual(history.latestTimestamp, date(121))
    }

    func testLongGapEvictsExpiredStorageOnNextAcceptedSample() {
        var history = MetricHistory()
        history.record(42, at: origin)
        history.record(7, at: date(172_800))
        XCTAssertEqual(history.rawSampleCount, 1)
        XCTAssertEqual(history.hourBucketCount, 1)
        XCTAssertEqual(history.dayBucketCount, 1)
        for range in HistoryRange.allCases {
            XCTAssertEqual(
                history.points(in: range, endingAt: date(172_800)),
                [TimedMetricSample(timestamp: date(172_800), value: 7)])
        }
    }

    func testTwoDaysOfOneSecondSamplesHaveBoundedOrderedTiers() {
        var history = MetricHistory()
        for second in 0...172_800 {
            history.record(Double(second % 100), at: date(Double(second)))
        }
        XCTAssertEqual(history.rawSampleCount, 301)
        XCTAssertLessThanOrEqual(history.hourBucketCount, MetricHistory.hourCapacity)
        XCTAssertLessThanOrEqual(history.dayBucketCount, MetricHistory.dayCapacity)
        for range in HistoryRange.allCases {
            let points = history.points(in: range, endingAt: date(172_800))
            XCTAssertEqual(points.last?.timestamp, date(172_800))
            XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
            XCTAssertTrue(points.allSatisfy { $0.timestamp >= date(172_800 - range.duration) })
            let limit =
                range == .fiveMinutes
                ? MetricHistory.rawCapacity
                : (range == .oneHour ? MetricHistory.hourCapacity : MetricHistory.dayCapacity)
            XCTAssertLessThanOrEqual(points.count, limit)
        }
        XCTAssertTrue(history.points(in: .oneDay, endingAt: date(345_601)).isEmpty)
    }

    func testHardRawCapHandlesUnexpectedHighFrequencyWithoutLosingAggregateInputs() throws {
        var history = MetricHistory()
        for index in 0..<10_000 {
            history.record(Double(index), at: date(Double(index) / 1_000))
        }
        XCTAssertEqual(history.rawSampleCount, MetricHistory.rawCapacity)
        XCTAssertEqual(history.hourBucketCount, 1)
        XCTAssertEqual(history.dayBucketCount, 1)
        let points = history.points(in: .fiveMinutes, endingAt: date(10))
        XCTAssertEqual(points.first?.value, Double(10_000 - MetricHistory.rawCapacity))
        XCTAssertEqual(points.last?.timestamp, date(9.999))
        let bucket = try XCTUnwrap(history.points(in: .oneHour, endingAt: date(10)).first)
        XCTAssertEqual(bucket.value, 4_999.5, accuracy: 1e-9)
    }

    func testBucketsWorkBeforeReferenceEpoch() {
        var history = MetricHistory()
        history.record(2, at: date(-11))
        history.record(4, at: date(-9))
        history.record(6, at: date(-1))
        history.record(8, at: date(0))
        XCTAssertEqual(history.points(in: .oneHour, endingAt: origin).map(\.value), [2, 5, 8])
        XCTAssertEqual(history.points(in: .oneDay, endingAt: origin).map(\.value), [4, 8])
    }

    func testPartialHistoryUsesTimeWindowNotArrayWidthAndNearestIsActualObservation() {
        var history = MetricHistory()
        history.record(2, at: date(290))
        history.record(4, at: date(295))
        let window = MetricHistoryWindow(history: history, range: .fiveMinutes, endingAt: date(300))
        XCTAssertEqual(window.startingAt, origin)
        XCTAssertEqual(window.fraction(at: date(290)), 290.0 / 300, accuracy: 1e-12)
        XCTAssertEqual(window.fraction(at: date(295)), 295.0 / 300, accuracy: 1e-12)
        XCTAssertEqual(window.nearestSample(to: 0)?.timestamp, date(290))
        XCTAssertEqual(window.nearestSample(to: 1)?.timestamp, date(295))
        XCTAssertEqual(window.nearestSample(to: 292.5 / 300)?.timestamp, date(290), "Ties select the earlier point")
        XCTAssertEqual(window.nearestSample(to: 293.0 / 300)?.timestamp, date(295))
        XCTAssertNil(window.nearestSample(to: .nan))
    }

    func testSelectionInGapNeverInventsSampleAndFractionClampsToWindow() {
        var history = MetricHistory()
        history.record(10, at: date(30))
        history.record(90, at: date(270))
        let window = MetricHistoryWindow(history: history, range: .fiveMinutes, endingAt: date(300))
        XCTAssertEqual(window.nearestSample(to: 0.4), TimedMetricSample(timestamp: date(30), value: 10))
        XCTAssertEqual(window.nearestSample(to: 0.6), TimedMetricSample(timestamp: date(270), value: 90))
        XCTAssertEqual(window.nearestSample(to: -1)?.timestamp, date(30))
        XCTAssertEqual(window.nearestSample(to: 2)?.timestamp, date(270))
        XCTAssertEqual(window.fraction(at: date(-1)), 0)
        XCTAssertEqual(window.fraction(at: date(301)), 1)
    }

    func testFrozenCopyRetainsAllTiersAndAnchorWhileOriginalContinuesRecording() {
        var live = MetricHistory()
        live.record(2, at: date(1))
        live.record(4, at: date(2))
        let frozen = live
        let frozenWindow = MetricHistoryWindow(history: frozen, range: .oneHour, endingAt: date(3))
        live.record(100, at: date(4))  // Same bucket: must not mutate frozen aggregate.
        live.record(9, at: date(172_800))  // Evicts everything from live.
        XCTAssertEqual(frozen.latestTimestamp, date(2))
        XCTAssertEqual(live.latestTimestamp, date(172_800))
        XCTAssertEqual(frozenWindow.endingAt, date(3))
        XCTAssertEqual(frozenWindow.points, [TimedMetricSample(timestamp: date(2), value: 3)])
        XCTAssertEqual(frozen.points(in: .fiveMinutes, endingAt: date(3)).map(\.value), [2, 4])
        XCTAssertEqual(frozen.points(in: .oneDay, endingAt: date(3)).first?.value, 3)
        XCTAssertEqual(live.points(in: .oneHour, endingAt: date(172_800)).first?.value, 9)
    }
}
